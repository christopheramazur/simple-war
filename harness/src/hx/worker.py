"""Background job queue and local-model lifecycle (DESIGN.md §7, Q33; sw-lbm.16).

Jobs come from client hooks (Claude Code SessionEnd, the OpenCode plugin) via `hx worker enqueue`
and are run by `hx worker run` (a detached loop started with `hx worker start`).

- Queue: SQLite at data/worker/queue.sqlite. Not the DuckDB ledger: DuckDB locks its file
  across processes, and hooks enqueue while the worker or `hx ingest` hold it.
- Local model: a job with needs_local starts Bonsai only when about 11 GB of VRAM is free, and
  waits otherwise. The worker stops Bonsai after 10 idle minutes, but only if the worker
  started it.
- `hx delegate` jumps the queue: while its lock file is fresh, the worker takes no local jobs.
"""

from __future__ import annotations

import json
import sqlite3
import time
from collections.abc import Callable
from datetime import datetime, timezone
from pathlib import Path

from hx import paths

IDLE_STOP_S = 600
POLL_S = 5
MAX_ATTEMPTS = 3
DELEGATE_LOCK_STALE_S = 1800

SCHEMA = """
CREATE TABLE IF NOT EXISTS job (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL,
  payload TEXT NOT NULL DEFAULT '{}',
  needs_local INTEGER NOT NULL DEFAULT 0,
  priority INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending',   -- pending | running | done | failed
  attempts INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  started_at TEXT,
  finished_at TEXT,
  result TEXT
);
CREATE INDEX IF NOT EXISTS job_next ON job (status, priority DESC, id);
"""


def state_dir() -> Path:
    d = paths.data_dir() / "worker"
    d.mkdir(parents=True, exist_ok=True)
    return d


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def connect() -> sqlite3.Connection:
    con = sqlite3.connect(state_dir() / "queue.sqlite", timeout=10, isolation_level=None)
    con.row_factory = sqlite3.Row
    con.executescript(SCHEMA)
    return con


# ---------------- handlers ----------------

Handler = Callable[[dict], str]
HANDLERS: dict[str, tuple[Handler, bool]] = {}  # kind -> (fn(payload) -> result text, needs_local)


def handler(kind: str, needs_local: bool = False):
    def deco(fn: Handler) -> Handler:
        HANDLERS[kind] = (fn, needs_local)
        return fn
    return deco


@handler("ingest")
def _ingest(payload: dict) -> str:
    import argparse

    from hx.commands import ingest
    r = ingest.run(argparse.Namespace(rebuild=False))
    if r.exit_code:
        raise RuntimeError("; ".join(f"{c.name}: {c.detail}" for c in r.checks if c.status == "fail"))
    return ", ".join(f"{k} {v}" for k, v in r.data.items())[:500]


@handler("session_end")
def _session_end(payload: dict) -> str:
    """A client session finished: refresh the ledger. Per-session follow-ups (tagging, sw-lbm.17;
    mining, sw-lbm.18) register their own handlers and get enqueued from here."""
    out = _ingest(payload)
    for kind in FOLLOW_UPS:
        enqueue(kind, payload)
    return out


FOLLOW_UPS: list[str] = ["tag_session", "mine", "reflect"]  # job kinds enqueued after every session_end


@handler("mine")
def _mine(payload: dict) -> str:
    """Mine repeated commands into hx verb candidates (DESIGN.md §5); throttled inside mining.run."""
    from hx import ledger, mining
    con = ledger.read_only()
    try:
        out = mining.run(con)
    finally:
        con.close()
    return out.get("skipped") or f"{out['candidates']} candidates, filed {[f['issue'] for f in out['filed']]}"


@handler("reflect")
def _reflect(payload: dict) -> str:
    """Weekly reflection, proposals only (DESIGN.md §9); throttled inside reflection.run."""
    from hx import ledger, reflection
    con = ledger.read_only()
    try:
        out = reflection.run(con)
    finally:
        con.close()
    return out.get("skipped") or f"filed {[p['issue'] for p in out['proposals'] if p.get('issue')]}"


@handler("tag_session")
def _tag_session(payload: dict) -> str:
    """Tag a finished session (DESIGN.md §3); session_end ran ingest first, so the raw copy exists.
    The delegate call starts or falls back from the local model by itself."""
    from hx import tagging
    sid = payload.get("session_id")
    if not sid:
        return "skipped: no session id"
    rows = tagging.tag_session(sid)
    return "; ".join(f"{r['role']} {r.get('kind')}/{r.get('outcome')} {r.get('problem') or ''}".strip()
                     for r in rows) or "already tagged"


# ---------------- queue ----------------

def enqueue(kind: str, payload: dict | None = None, priority: int = 0) -> int:
    """Job id. A pending job of the same kind for the same session is reused (OpenCode fires per turn)."""
    needs_local = HANDLERS.get(kind, (None, False))[1]
    con = connect()
    try:
        sid = (payload or {}).get("session_id")
        if sid:
            dup = con.execute("SELECT id FROM job WHERE status = 'pending' AND kind = ? "
                              "AND json_extract(payload, '$.session_id') = ?", (kind, sid)).fetchone()
            if dup:
                return dup["id"]
        cur = con.execute("INSERT INTO job (kind, payload, needs_local, priority, created_at) VALUES (?, ?, ?, ?, ?)",
                          (kind, json.dumps(payload or {}), int(needs_local), priority, _now()))
        return cur.lastrowid
    finally:
        con.close()


def claim(con: sqlite3.Connection, allow_local: bool) -> sqlite3.Row | None:
    """Take the next pending job (atomic across processes)."""
    con.execute("BEGIN IMMEDIATE")
    try:
        row = con.execute(
            "SELECT * FROM job WHERE status = 'pending'" + ("" if allow_local else " AND needs_local = 0")
            + " ORDER BY priority DESC, id LIMIT 1").fetchone()
        if row:
            con.execute("UPDATE job SET status = 'running', started_at = ?, attempts = attempts + 1 WHERE id = ?",
                        (_now(), row["id"]))
        con.execute("COMMIT")
        return row
    except Exception:
        con.execute("ROLLBACK")
        raise


def execute(con: sqlite3.Connection, row: sqlite3.Row) -> bool:
    fn = HANDLERS.get(row["kind"], (None, False))[0]
    try:
        if fn is None:
            raise KeyError(f"no handler for job kind {row['kind']!r}")
        result, status = fn(json.loads(row["payload"])), "done"
    except Exception as e:
        result = f"{type(e).__name__}: {e}"[:500]
        # row was read before claim() bumped attempts
        status = "failed" if fn is None or row["attempts"] + 1 >= MAX_ATTEMPTS else "pending"
    con.execute("UPDATE job SET status = ?, finished_at = ?, result = ? WHERE id = ?",
                (status, _now(), result, row["id"]))
    return status == "done"


def counts(con: sqlite3.Connection) -> dict[str, int]:
    return {r["status"]: r["n"] for r in con.execute("SELECT status, count(*) AS n FROM job GROUP BY status")}


def recover(con: sqlite3.Connection) -> int:
    """Jobs left 'running' by a killed worker go back to pending."""
    return con.execute("UPDATE job SET status = 'pending' WHERE status = 'running'").rowcount


# ---------------- delegate lock ----------------

def delegate_lock() -> Path:
    return state_dir() / "delegate.lock"


def delegate_active() -> bool:
    f = delegate_lock()
    return f.exists() and time.time() - f.stat().st_mtime < DELEGATE_LOCK_STALE_S


# ---------------- local model lifecycle ----------------

class Lifecycle:
    """Starts the local model for local jobs and stops it after IDLE_STOP_S, if this worker started it."""

    def __init__(self, pid: str = "bonsai", lm=None, clock=time.time, mtime=lambda p: p.stat().st_mtime):
        if lm is None:
            from hx import localmodel as lm
        self.pid, self.lm, self.clock, self.mtime = pid, lm, clock, mtime
        self.started_by_us = (state_dir() / f"{pid}.started").exists()
        self.last_used = clock()

    def ensure(self) -> str | None:
        """None when the model is up, else why it can't be."""
        if self.lm.alive(self.pid):
            return None
        why = self.lm.can_start(self.pid)
        if why:
            return f"waiting: {why}"
        ok, msg = self.lm.start(self.pid)
        if not ok:
            return msg
        self.started_by_us = True
        (state_dir() / f"{self.pid}.started").write_text(_now())
        return None

    def touch(self) -> None:
        self.last_used = self.clock()

    def maybe_stop(self, busy: bool) -> bool:
        # hx delegate also writes the marker when it starts the model (and refreshes it after each
        # local call), so it gets idled too; idle time counts from the marker, never from before it.
        marker = state_dir() / f"{self.pid}.started"
        if marker.exists():
            self.started_by_us = True
            self.last_used = max(self.last_used, self.mtime(marker))
        if busy or not self.started_by_us or self.clock() - self.last_used < IDLE_STOP_S:
            return False
        if self.lm.alive(self.pid):
            self.lm.stop(self.pid)
        self.started_by_us = False
        (state_dir() / f"{self.pid}.started").unlink(missing_ok=True)
        return True


def tick(con: sqlite3.Connection, life: Lifecycle, log=print) -> bool:
    """Run at most one job. True if one ran."""
    pending_local = con.execute("SELECT count(*) FROM job WHERE status = 'pending' AND needs_local = 1").fetchone()[0]
    allow_local = False
    if pending_local and not delegate_active():
        why = life.ensure()
        allow_local = why is None
        if why:
            log(f"local jobs waiting: {why}")
    row = claim(con, allow_local)
    if row is None:
        life.maybe_stop(busy=delegate_active())
        return False
    t0 = time.perf_counter()
    ok = execute(con, row)
    if row["needs_local"]:
        life.touch()
    log(f"job {row['id']} {row['kind']} {'ok' if ok else 'FAILED'} {time.perf_counter() - t0:.1f}s")
    return True


def loop(once: bool = False, log=print) -> None:
    con = connect()
    n = recover(con)
    if n:
        log(f"recovered {n} interrupted job(s)")
    life = Lifecycle()
    (state_dir() / "worker.heartbeat").write_text(_now())
    while True:
        ran = tick(con, life, log)
        (state_dir() / "worker.heartbeat").write_text(_now())
        if once and not ran:
            return
        if not ran:
            time.sleep(POLL_S)
