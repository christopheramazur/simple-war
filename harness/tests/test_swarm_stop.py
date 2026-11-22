"""Stopping the swarm ends its running turns instead of orphaning them (sw-0zi.11)."""

from __future__ import annotations

import json
import sys
import threading
import time
from types import SimpleNamespace

import pytest

from hx import keystore, swarm


@pytest.fixture
def env(tmp_path, monkeypatch):
    monkeypatch.setattr(swarm, "STATE", tmp_path / "state")
    monkeypatch.setattr(swarm, "ensure_gateway", lambda: None)
    monkeypatch.setattr(swarm, "opencode_exe", lambda: sys.executable)
    monkeypatch.setattr(keystore, "get", lambda name: "test-key")
    monkeypatch.setattr(swarm, "update_state", lambda fn: {})
    # `python run ...` runs the script named "run" in the turn's cwd: a stand-in for a long OpenCode turn.
    (tmp_path / "run").write_text("import time\ntime.sleep(120)\n", encoding="utf-8")
    swarm._stopping.clear()
    yield tmp_path
    swarm._stopping.clear()


def events(tmp_path):
    f = tmp_path / "state" / "events.jsonl"
    return [json.loads(line) for line in f.read_text(encoding="utf-8").splitlines()] if f.exists() else []


def test_stop_turns_ends_a_running_turn(env):
    result = {}
    t = threading.Thread(target=lambda: result.update(rc=swarm.run_turn("worker-sw-x", "p", cwd=env, timeout=600)[0]))
    t.start()
    deadline = time.time() + 20
    while not swarm._running and time.time() < deadline:
        time.sleep(0.05)
    assert swarm._running, "the turn never started"
    proc = next(iter(swarm._running.values()))
    killed = swarm.stop_turns()
    t.join(30)
    assert not t.is_alive()
    assert killed == [proc.pid]
    assert result["rc"] == swarm.STOPPED
    assert proc.poll() is not None
    assert swarm._running == {}
    e = events(env)[-1]
    assert e["kind"] == "turn" and e["rc"] == swarm.STOPPED and e["stopped"] is True


def test_turn_timeout_still_kills(env):
    rc, _ = swarm.run_turn("auditor", "p", cwd=env, timeout=1)
    assert rc == -9
    assert "stopped" not in events(env)[-1]


def test_stopped_worker_goes_back_in_the_queue(env, monkeypatch):
    job = {"bead": "sw-x", "status": "queued", "attempts": 1, "worktree": str(env), "branch": "swarm/sw-x",
           "base": "abc1234567", "bead_text": "text"}
    saved = []
    monkeypatch.setattr(swarm, "jobs", lambda: [job])
    monkeypatch.setattr(swarm, "save_job", lambda j: saved.append(dict(j)))
    monkeypatch.setattr(swarm, "save_wip", lambda wt, why: True)
    monkeypatch.setattr(swarm, "git", lambda *a, **k: SimpleNamespace(stdout="2\n"))
    monkeypatch.setattr(swarm, "compose", lambda *a, **k: "prompt")
    mail = []
    monkeypatch.setattr(swarm, "send_mail", lambda *a: mail.append(a))
    s = swarm.Supervisor.__new__(swarm.Supervisor)
    s.c = {"workers": {"max_parallel": 1, "timeout_s": 7200}, "run": {"end_at": "2099-01-01T00:00:00+00:00"}}
    s.end = swarm.datetime.fromisoformat(s.c["run"]["end_at"])
    s.stop = threading.Event()

    def turn(*a, **k):
        s.stop.set()
        return swarm.STOPPED, ""
    s.turn = turn
    s.worker_loop(0)
    assert saved[-1]["status"] == "queued" and saved[-1]["commits"] == 2
    assert events(env)[-1] == {**events(env)[-1], "kind": "worker_done", "status": "stopped", "wip": True}
    assert mail == []  # nothing for the orchestrator to review


def test_stop_waits_then_kills_what_the_supervisor_left(env, monkeypatch):
    pids = iter([123, 123, None])
    monkeypatch.setattr(swarm, "supervisor_pid", lambda: next(pids, None))
    monkeypatch.setattr(swarm, "children", lambda pid: [7, 8] if pid == 123 else [])
    killed = []
    monkeypatch.setattr(swarm.background, "kill_tree", lambda pid: killed.append(pid))
    monkeypatch.setattr(swarm.time, "sleep", lambda s: None)
    out = swarm.stop(wait_s=60)
    assert out == {"was_running": True, "exited": True, "orphans_killed": [7, 8]}
    assert killed == [7, 8]
    assert (env / "state" / "STOP").exists()


def test_stop_kills_nothing_while_the_supervisor_still_runs(env, monkeypatch):
    monkeypatch.setattr(swarm, "supervisor_pid", lambda: 123)
    monkeypatch.setattr(swarm, "children", lambda pid: [7])
    killed = []
    monkeypatch.setattr(swarm.background, "kill_tree", lambda pid: killed.append(pid))
    out = swarm.stop(wait_s=0.1)
    assert out["exited"] is False and killed == []


def test_stop_without_a_supervisor(env, monkeypatch):
    monkeypatch.setattr(swarm, "supervisor_pid", lambda: None)
    assert swarm.stop() == {"was_running": False, "exited": True, "orphans_killed": []}
