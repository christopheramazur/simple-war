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
