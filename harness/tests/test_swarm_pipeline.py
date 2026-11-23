"""The supervisor's own pipeline steps and the event-driven orchestrator (sw-0zi.3)."""

from __future__ import annotations

import threading
import time
from datetime import timedelta

import pytest

from hx import swarm

C = {"workers": {"max_parallel": 1, "max_open": 4, "auto_refill": True, "refill_idle_min": 10, "review_timeout_min": 90,
                 "refill_exclude_labels": ["needs-human", "swarm-harness"], "refill_exclude_parents": ["sw-p2q"]},
     "orchestrator": {"heartbeat_s": 3600}, "run": {"end_at": "2099-01-01T00:00:00+00:00"}}


def bead(id, priority=2, type="task", labels=None, parent=None, title="t", description="", created="2026-11-01"):
    return {"id": id, "priority": priority, "issue_type": type, "labels": labels, "parent": parent, "title": title,
            "description": description, "created_at": created}


def test_bead_paths():
    text = "Fix `src/sim/battle/combat_system.gd` and tests/sim/test_x.gd; see harness/src/hx/swarm.py. Not foo/bar."
    assert swarm.bead_paths(text) == {"src/sim/battle/combat_system.gd", "tests/sim/test_x.gd", "harness/src/hx/swarm.py"}


def test_pick_ready_filters():
    ready = [bead("sw-epic", 0, type="epic"), bead("sw-par", 0), bead("sw-h", 0, labels=["needs-human"]),
             bead("sw-g", 0, labels=["swarm-harness"]), bead("sw-p2q.2", 0, parent="sw-p2q"),
             bead("sw-di", 0, title="Design interview: timeline"), bead("sw-job", 0),
             bead("sw-overlap", 0, description="edit src/presentation/war_room/squad_card.gd"),
             bead("sw-ok", 3)]
    open_beads = ready + [bead("sw-par.1", parent="sw-par")]
    busy = ["worker on src/presentation/war_room"]
    assert swarm.pick_ready(ready, open_beads, busy, C, skip={"sw-job"})["id"] == "sw-ok"


def test_pick_ready_order():
    ready = [bead("sw-old", 1, created="2026-11-01"), bead("sw-prop", 1, labels=["swarm-proposed"], created="2026-11-05"),
             bead("sw-bug", 1, type="bug", created="2026-11-09"), bead("sw-p0", 0, created="2026-11-10")]
    order = []
    while ready:
        b = swarm.pick_ready(ready, ready, [], C)
        order.append(b["id"])
        ready = [x for x in ready if x is not b]
    assert order == ["sw-p0", "sw-bug", "sw-prop", "sw-old"]


@pytest.fixture
def sv(tmp_path, monkeypatch):
    monkeypatch.setattr(swarm, "STATE", tmp_path / "state")
    s = swarm.Supervisor.__new__(swarm.Supervisor)
    s.c = {k: dict(v) for k, v in C.items()}
    s.end = swarm.datetime.fromisoformat(C["run"]["end_at"])
    s.stop = threading.Event()
    s.orch_running = threading.Event()
    s.mail = []
    monkeypatch.setattr(swarm, "send_mail", lambda to, sender, body: s.mail.append(body))
    return s


def test_orchestrator_wakes_on_mail(sv, tmp_path, monkeypatch):
    monkeypatch.setattr(sv, "wait", lambda seconds: time.sleep(0.01))
    (tmp_path / "state" / "mail" / "orchestrator").mkdir(parents=True)
    (tmp_path / "state" / "mail" / "orchestrator" / "x.md").write_text("hi", encoding="utf-8")
    assert sv.wait_for_orchestrator_work() == "1 new message(s) in your inbox"


def test_orchestrator_heartbeat_without_mail(sv, monkeypatch):
    monkeypatch.setattr(sv, "wait", lambda seconds: time.sleep(0.01))
    sv.c["orchestrator"]["heartbeat_s"] = 0.05
    assert "heartbeat" in sv.wait_for_orchestrator_work()


@pytest.fixture
def pipe(sv, monkeypatch):
    sv.jobs, sv.events, sv.spawned, sv.bd_calls, sv.merges = [], [], [], [], []
    sv.merge_error = None
    monkeypatch.setattr(swarm, "jobs", lambda: sv.jobs)
    monkeypatch.setattr(swarm, "save_job", lambda j: None)
    monkeypatch.setattr(swarm, "events", lambda since=None: sv.events)
    monkeypatch.setattr(swarm, "_bd_json", lambda *a: [bead("sw-next", 1, description="data/x.json")] if a[0] == "ready" else [])
    monkeypatch.setattr(swarm, "_bd", lambda *a: sv.bd_calls.append(a))
    monkeypatch.setattr(swarm, "spawn_worker", lambda b, note="", fresh=False: sv.spawned.append(b))

    def merge(b):
        if sv.merge_error:
            raise ValueError(sv.merge_error)
        sv.merges.append(b)
        return "merged (godot test green)"
    monkeypatch.setattr(swarm, "merge_worker", merge)
    return sv


def test_refill_spawns_when_a_slot_sat_idle(pipe):
    assert pipe.refill() == "sw-next"
    assert pipe.spawned == ["sw-next"] and ("update", "sw-next", "--claim") in pipe.bd_calls
    assert "Auto-refill" in pipe.mail[-1]


def test_refill_waits_for_the_orchestrator_first(pipe):
    pipe.events = [{"ts": swarm.now().isoformat(), "kind": "worker_done"}]
    assert pipe.refill() is None


def test_refill_respects_slots_and_switch(pipe):
    pipe.jobs = [{"bead": "sw-a", "status": "running", "bead_text": ""}]
    assert pipe.refill() is None
    pipe.jobs = []
    pipe.c["workers"]["auto_refill"] = False
    assert pipe.refill() is None
    assert pipe.spawned == []


def done_job(bead="sw-a", status="done", minutes=120, commits=2):
    return {"bead": bead, "status": status, "commits": commits,
            "finished": (swarm.now() - timedelta(minutes=minutes)).isoformat(timespec="seconds")}


def test_auto_merge_unreviewed_done_worker_once(pipe):
    pipe.jobs = [done_job(), done_job("sw-p", status="partial"), done_job("sw-new", minutes=20), done_job("sw-0", commits=0)]
    assert pipe.auto_merge() == ["sw-a"]
    assert any(c[:3] == ("update", "sw-a", "--add-label=swarm-unreviewed") for c in pipe.bd_calls)
    assert "Auto-merged sw-a" in pipe.mail[-1]
    assert pipe.auto_merge() == []  # tried once
    assert pipe.merges == ["sw-a"]


def test_failed_auto_merge_goes_back_to_the_orchestrator(pipe):
    pipe.jobs = [done_job()]
    pipe.merge_error = "tests failed on the merged branch"
    assert pipe.auto_merge() == []
    assert "Auto-merge of sw-a" in pipe.mail[-1] and "tests failed" in pipe.mail[-1]
    pipe.merge_error = None
    assert pipe.auto_merge() == []  # not retried


def test_no_auto_merge_while_the_orchestrator_runs(pipe):
    pipe.jobs = [done_job()]
    pipe.orch_running.set()
    assert pipe.auto_merge() == [] and pipe.merges == []
    pipe.orch_running.clear()
    assert pipe.auto_merge() == ["sw-a"]
