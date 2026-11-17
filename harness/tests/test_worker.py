import json

import pytest

from hx import worker


class FakeLM:
    def __init__(self, free=12000, up=False):
        self.free, self.up, self.starts, self.stops = free, up, 0, 0

    def alive(self, pid):
        return self.up

    def vram_used_mib(self):
        return 12288 - self.free

    def vram_total_mib(self):
        return 12288

    def can_start(self, pid):
        return None if self.free >= 11000 else f"{self.free} MiB free"

    def start(self, pid):
        self.up, self.starts = True, self.starts + 1
        return True, "ok"

    def stop(self, pid):
        self.up, self.stops = False, self.stops + 1
        return "stopped"


class Clock:
    t = 1000.0

    def __call__(self):
        return self.t


@pytest.fixture(autouse=True)
def tmp_data(tmp_path, monkeypatch):
    monkeypatch.setenv("HX_DATA_DIR", str(tmp_path))
    ran = []
    monkeypatch.setitem(worker.HANDLERS, "cheap", (lambda p: ran.append(("cheap", p)) or "ok", False))
    monkeypatch.setitem(worker.HANDLERS, "gpu", (lambda p: ran.append(("gpu", p)) or "ok", True))
    monkeypatch.setitem(worker.HANDLERS, "boom", (lambda p: 1 / 0, False))
    return ran


def test_priority_then_fifo_and_retry_then_fail(tmp_data):
    a = worker.enqueue("cheap", {"n": 1})
    worker.enqueue("cheap", {"n": 2}, priority=5)
    worker.enqueue("boom")
    con = worker.connect()
    life = worker.Lifecycle(lm=FakeLM())
    while worker.tick(con, life, log=lambda m: None):
        pass
    assert [p["n"] for _, p in tmp_data] == [2, 1] and a == 1
    row = con.execute("SELECT status, attempts, result FROM job WHERE kind = 'boom'").fetchone()
    assert (row["status"], row["attempts"]) == ("failed", worker.MAX_ATTEMPTS) and "ZeroDivision" in row["result"]


def test_unknown_kind_fails_once():
    worker.enqueue("nope")
    con = worker.connect()
    worker.tick(con, worker.Lifecycle(lm=FakeLM()), log=lambda m: None)
    assert worker.counts(con) == {"failed": 1}


def test_local_job_waits_for_vram_then_starts(tmp_data):
    lm = FakeLM(free=8000)
    worker.enqueue("gpu")
    con = worker.connect()
    life = worker.Lifecycle(lm=lm)
    assert not worker.tick(con, life, log=lambda m: None) and lm.starts == 0
    lm.free = 11500
    assert worker.tick(con, life, log=lambda m: None) and lm.starts == 1 and tmp_data == [("gpu", {})]


def test_idle_stop_only_if_we_started_it():
    clock, lm = Clock(), FakeLM()
    life = worker.Lifecycle(lm=lm, clock=clock, mtime=lambda p: 1000.0)  # marker written at start
    life.ensure()
    clock.t += worker.IDLE_STOP_S - 1
    assert not life.maybe_stop(busy=False)
    clock.t += 2
    assert life.maybe_stop(busy=False) and lm.stops == 1
    lm2 = FakeLM(up=True)  # already running when the worker came up: never stopped by us
    life2 = worker.Lifecycle(lm=lm2, clock=clock)
    clock.t += 10_000
    assert not life2.maybe_stop(busy=False) and lm2.stops == 0


def test_delegate_lock_holds_local_jobs(tmp_data):
    worker.enqueue("gpu")
    worker.delegate_lock().write_text("x")
    con = worker.connect()
    assert not worker.tick(con, worker.Lifecycle(lm=FakeLM()), log=lambda m: None)
    worker.delegate_lock().unlink()
    assert worker.tick(con, worker.Lifecycle(lm=FakeLM()), log=lambda m: None)


def test_recover_running_jobs():
    worker.enqueue("cheap")
    con = worker.connect()
    worker.claim(con, allow_local=False)
    assert worker.recover(con) == 1 and worker.counts(con) == {"pending": 1}


def test_pending_job_per_session_is_deduped():
    a = worker.enqueue("cheap", {"session_id": "s1"})
    assert worker.enqueue("cheap", {"session_id": "s1"}) == a
    assert worker.enqueue("cheap", {"session_id": "s2"}) != a


def test_model_started_by_delegate_is_idled_from_marker_time():
    clock, lm = Clock(), FakeLM(up=True)
    marked = {}
    life = worker.Lifecycle(lm=lm, clock=clock, mtime=lambda p: marked["t"])
    clock.t += 5000  # worker has been up a long time before anything is started
    (worker.state_dir() / "bonsai.started").write_text("delegate")
    marked["t"] = clock.t
    assert not life.maybe_stop(busy=False) and lm.stops == 0  # just started: not idle yet
    clock.t += worker.IDLE_STOP_S + 1
    assert life.maybe_stop(busy=False) and lm.stops == 1


def _ledger_with(tmp_path, last_call: dict):
    """A ledger whose sessions had their last call at the given UTC datetimes."""
    from hx import ledger
    con = ledger.connect(tmp_path / "l.duckdb")
    for sid, ts in last_call.items():
        ledger.upsert(con, "session", [{"session_id": sid, "client": "claude-code"}])
        ledger.upsert(con, "call", [{"call_id": f"c{sid}", "session_id": sid, "ts": ts, "client": "claude-code"}])
    return con


def test_periodic_tags_idle_sessions_only_and_is_throttled(tmp_path):
    from datetime import datetime, timezone
    utc = lambda h: datetime(2026, 11, 17, h)  # the ledger stores naive UTC
    now = datetime(2026, 11, 17, 23, tzinfo=timezone.utc).timestamp()
    con = _ledger_with(tmp_path, {"old": utc(1), "older": utc(0), "live": utc(22)})
    ids = worker.periodic(con, now)
    q = worker.connect()
    jobs = [(r["kind"], json.loads(r["payload"]).get("session_id")) for r in
            q.execute("SELECT kind, payload FROM job WHERE id IN (%s) ORDER BY id" % ",".join(map(str, ids)))]
    assert jobs == [("mine", None), ("reflect", None), ("tag_session", "old"), ("tag_session", "older")]
    assert worker.periodic(con, now + 60) == [], "throttled for PERIODIC_S"
    # A session already queued (or failed for good) is not picked again.
    assert worker.idle_untagged(con, now) == []


def test_tag_job_skips_a_session_that_wrote_no_transcript(tmp_path):
    out = worker.HANDLERS["tag_session"][0]({"session_id": "ghost", "transcript_path": str(tmp_path / "ghost.jsonl")})
    assert out.startswith("skipped")


def test_worker_exits_when_idle_and_stops_what_it_started(monkeypatch):
    from hx.gateway import process
    lm, clock = FakeLM(), Clock()
    life = worker.Lifecycle(lm=lm, clock=clock)
    assert life.ensure() is None and lm.up  # the worker started the model
    stopped = []
    monkeypatch.setattr(process, "STARTED_HERE", True)
    monkeypatch.setattr(process, "stop", lambda: stopped.append(1) or "stopped")

    def sleep(s):
        clock.t += s
    worker.loop(log=lambda m: None, idle_exit_s=60, clock=clock, sleep=sleep, life=life)
    assert clock.t - 1000.0 >= 60, "it waited out the idle time, then returned"
    assert not lm.up and lm.stops == 1 and stopped == [1]
    assert not (worker.state_dir() / "bonsai.started").exists()


def test_worker_leaves_a_model_it_did_not_start(monkeypatch):
    from hx.gateway import process
    lm = FakeLM(up=True)
    monkeypatch.setattr(process, "STARTED_HERE", False)
    monkeypatch.setattr(process, "stop", lambda: pytest.fail("gateway was not ours"))
    worker.loop(once=True, log=lambda m: None, life=worker.Lifecycle(lm=lm, clock=Clock()))
    assert lm.up and lm.stops == 0
