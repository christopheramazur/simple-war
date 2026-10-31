"""hx worker: background job queue + local-model lifecycle (DESIGN.md §7, Q33).

  hx worker enqueue session_end --hook      payload from a client hook's stdin JSON
  hx worker enqueue ingest
  hx worker start | stop | status
  hx worker run [--once]                    the loop itself (foreground)
"""

from __future__ import annotations

import argparse
import json
import sys

from hx.output import FAIL, OK, WARN, Check, Result

HELP = "Background job queue and Bonsai lifecycle: enqueue | start | stop | status | run"


def add_args(p) -> None:
    sub = p.add_subparsers(dest="action", required=True, metavar="<action>")
    for name in ("enqueue", "start", "stop", "status", "run"):
        sp = sub.add_parser(name)
        sp.add_argument("--json", action="store_true", default=argparse.SUPPRESS)
        sp.add_argument("-v", "--verbose", action="store_true", default=argparse.SUPPRESS)
        if name == "enqueue":
            sp.add_argument("kind")
            sp.add_argument("--payload", default="{}", help="JSON object")
            sp.add_argument("--hook", action="store_true",
                            help="read a client hook's JSON from stdin; keep session_id, transcript_path, cwd")
            sp.add_argument("--client", default="claude-code")
            sp.add_argument("--priority", type=int, default=0)
        if name == "run":
            sp.add_argument("--once", action="store_true", help="drain the queue, then exit")


def run(args) -> Result:
    return {"enqueue": _enqueue, "start": _start, "stop": _stop, "status": _status, "run": _run}[args.action](args)


def _enqueue(args) -> Result:
    from hx import worker
    r = Result("worker enqueue")
    payload = json.loads(args.payload)
    if args.hook:
        try:
            hook = json.loads(sys.stdin.read() or "{}")
        except ValueError:
            hook = {}
        payload.update({k: hook[k] for k in ("session_id", "transcript_path", "cwd", "reason") if k in hook})
    payload.setdefault("client", args.client)
    if args.kind not in worker.HANDLERS:
        r.checks.append(Check("kind", WARN, f"no handler yet for {args.kind!r}; it will fail when run"))
    r.data["job"] = worker.enqueue(args.kind, payload, args.priority)
    return r


def _pid_file():
    from hx import worker
    return worker.state_dir() / "worker.pid"


def _running() -> str | None:
    import subprocess
    f = _pid_file()
    if not f.exists():
        return None
    pid = f.read_text().strip()
    if sys.platform == "win32":
        out = subprocess.run(["tasklist", "/FI", f"PID eq {pid}", "/NH"], capture_output=True, text=True).stdout
        return pid if pid in out else None
    try:
        import os
        os.kill(int(pid), 0)
        return pid
    except (OSError, ValueError):
        return None


def _start(args) -> Result:
    import os

    from hx import background, worker
    from hx.paths import HARNESS_ROOT
    r = Result("worker start")
    pid = _running()
    if pid:
        r.data["pid"] = pid
        r.checks.append(Check("worker", OK, "already running"))
        return r
    env = dict(os.environ, PYTHONPATH=str(HARNESS_ROOT / "src"), PYTHONUTF8="1")
    proc = background.spawn([sys.executable, "-m", "hx.cli", "worker", "run"], HARNESS_ROOT, env,
                            worker.state_dir() / "worker.log")
    _pid_file().write_text(str(proc.pid))
    r.data.update({"pid": proc.pid, "log": str(worker.state_dir() / "worker.log")})
    r.checks.append(Check("worker", OK))
    return r


def _stop(args) -> Result:
    from hx import background
    r = Result("worker stop")
    pid = _running()
    if pid:
        background.kill_tree(pid)
        r.data["stopped"] = pid
    else:
        r.data["stopped"] = "not running"
    _pid_file().unlink(missing_ok=True)
    return r


def _status(args) -> Result:
    from hx import worker
    r = Result("worker status")
    con = worker.connect()
    try:
        r.data["running"] = _running() or "no"
        hb = worker.state_dir() / "worker.heartbeat"
        r.data["heartbeat"] = hb.read_text() if hb.exists() else "never"
        r.data["jobs"] = worker.counts(con) or "none"
        r.data["bonsai_started_by_worker"] = (worker.state_dir() / "bonsai.started").exists()
        r.tables["recent"] = [dict(row) for row in con.execute(
            "SELECT id, kind, status, attempts, created_at, finished_at, substr(coalesce(result, ''), 1, 80) AS result "
            "FROM job ORDER BY id DESC LIMIT 10")]
        failed = con.execute("SELECT count(*) FROM job WHERE status = 'failed'").fetchone()[0]
    finally:
        con.close()
    if failed:
        r.checks.append(Check("failed jobs", WARN, f"{failed} failed; see the table"))
    return r


def _run(args) -> Result:
    from hx import worker
    r = Result("worker run")
    try:
        worker.loop(once=args.once, log=lambda m: print(f"{worker._now()} {m}", file=sys.stderr, flush=True))
    except KeyboardInterrupt:
        pass
    except Exception as e:
        r.checks.append(Check("loop", FAIL, f"{type(e).__name__}: {e}"))
    return r
