"""The deterministic swarm audit and the model auditor as an escalation only (sw-0zi.4)."""

from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone

import pytest

from hx import swarm

T = datetime(2026, 11, 21, 20, 0, tzinfo=timezone.utc)
C = {"audit": {"every_s": 1800, "window_min": 30, "turn_timeout_s": 2700, "fail_streak": 2},
     "orchestrator": {"turn_timeout_s": 3600, "pause_s": 240}, "workers": {"timeout_s": 7200}}


def calls(caller="swarm-orchestrator", model="nous/qwen4-max", n=10, limited=0, cost=0.0):
    return {"caller": caller, "model": model, "status": "success", "calls": n, "cost_usd": cost, "rate_limited": limited}


def digest(*rows, banners=None):
    return {"window_minutes": 30, "gateway_calls": list(rows),
            "swarm_log_model_banners": banners if banners is not None else {"nous/qwen4-max": 12}}


def ev(kind, minutes_ago, **kw):
    return {"ts": (T - timedelta(minutes=minutes_ago)).isoformat(), "kind": kind, **kw}


def ago(minutes):
    return (T - timedelta(minutes=minutes)).isoformat()


def verdict(u, events=(), js=(), **kw):
    kw.setdefault("orch_last", T - timedelta(minutes=10))
    return swarm.rule_verdict(C, u, list(events), list(js), T, **kw)


def test_clean_and_moving_is_pass():
    v = verdict(digest(calls()), [ev("merge", 30, bead="sw-a"), ev("worker", 40, role="worker-sw-a", rc=0)])
    assert v["verdict"] == "PASS", v
    assert "all nous/qwen4-max, cost 0 USD" in v["reason"]


@pytest.mark.parametrize("u, needle", [
    (digest(calls(model="anthropic/claude-x")), "non-Qwen model anthropic/claude-x"),
    (digest(calls(), banners={"nous/qwen4-max": 3, "openai/gpt-x": 1}), "non-Qwen model banners"),
    (digest(calls(cost=0.02)), "cost 0.0200 USD"),
])
def test_compliance_breaches_fail(u, needle):
    v = verdict(u)
    assert v["verdict"] == "FAIL" and needle in v["reason"], v


def test_non_swarm_callers_do_not_count():
    v = verdict(digest(calls(), calls(caller="-", model="anthropic/claude-x", cost=1.5)))
    assert v["verdict"] == "PASS", v


def test_silent_orchestrator_fails_unless_paused():
    assert "no orchestrator turn" in verdict(digest(calls()), orch_last=T - timedelta(hours=3))["reason"]
    assert verdict(digest(calls()), orch_last=T - timedelta(hours=3), paused=True)["verdict"] == "PASS"


def test_looping_orchestrator_fails_only_with_ready_work_and_idle_workers():
    loops = [ev("turn", m, role="orchestrator", rc=0) for m in (10, 40, 70, 100)]
    assert verdict(digest(calls()), loops, ready=5)["verdict"] == "FAIL"
    assert verdict(digest(calls()), loops, ready=0)["verdict"] == "PASS"
    assert verdict(digest(calls()), loops, [{"bead": "sw-a", "status": "running", "started": ago(30)}], ready=5)["verdict"] == "PASS"
    assert verdict(digest(calls()), loops + [ev("spawn", 50, bead="sw-a")], ready=5)["verdict"] == "PASS"


def test_actionable_warns():
    js = [{"bead": "sw-a", "status": "partial", "finished": ago(90)},
          {"bead": "sw-b", "status": "running", "started": ago(200)},
          {"bead": "sw-c", "status": "done", "finished": ago(20)}]
    reds = [ev("merge_red", 20, bead="sw-d"), ev("merge_red", 100, bead="sw-d"), ev("merge_red", 30, bead="sw-e")]
    v = verdict(digest(calls()), reds, js)
    assert v["verdict"] == "WARN"
    assert len(v["act"]) == 3, v["act"]
    assert any("sw-a finished (partial) 90 min" in x for x in v["act"])
    assert any("sw-b has run 200 min" in x for x in v["act"])
    assert any("sw-d failed the merge gate 2 times" in x for x in v["act"])
    assert not v["health"]


def test_throttling_is_health_not_actionable():
    v = verdict(digest(calls(n=20, limited=12)), [ev("worker", 60, role="worker-sw-a", rc=-9)])
    assert v["verdict"] == "WARN" and not v["act"]
    assert any("12/20 calls rate-limited" in x for x in v["health"])
    assert any("no merge in 2 h" in x for x in v["health"])


# ---------------------------------------------------------------- run_audit: when the model runs, what counts

@pytest.fixture
def sv(tmp_path, monkeypatch):
    monkeypatch.setattr(swarm, "STATE", tmp_path / "state")
    monkeypatch.setattr(swarm, "SWARM", tmp_path / "swarm")
    (tmp_path / "state").mkdir()
    s = swarm.Supervisor.__new__(swarm.Supervisor)
    s.c = {**C, "audit": {**C["audit"], "model_every_s": 14400, "model_min_gap_s": 3600}}
    s.orch_paused = swarm.threading.Event()
    s.model_turns, s.mail, s.postmortems = [], [], []
    s.model_says = None  # verdict the fake auditor records, or None (killed turn)
    s.u = digest(calls())
    s.js = []
    monkeypatch.setattr(swarm, "usage", lambda minutes: s.u)
    monkeypatch.setattr(swarm, "jobs", lambda: s.js)
    monkeypatch.setattr(swarm, "_ready_count", lambda: 3)
    monkeypatch.setattr(swarm, "_orchestrator_last", lambda: swarm.now() - timedelta(minutes=5))
    monkeypatch.setattr(swarm, "compose", lambda *a, **k: "prompt")
    monkeypatch.setattr(swarm, "send_mail", lambda to, sender, body: s.mail.append(body))
    s.postmortem = lambda v: s.postmortems.append(v)

    def fake_turn(role, prompt, **kw):
        s.model_turns.append(role)
        if s.model_says:
            swarm.event("verdict", verdict=s.model_says, reason="model reason", by="auditor")
        return (0 if s.model_says else -9), ""
    monkeypatch.setattr(swarm, "run_turn", fake_turn)
    swarm.update_state(lambda st: st.__setitem__("last_model_audit", swarm.now().isoformat()))
    return s


def verdicts(tmp_path):
    f = tmp_path / "state" / "events.jsonl"
    return [e for e in map(json.loads, f.read_text(encoding="utf-8").splitlines()) if e["kind"] == "verdict"]


def test_pass_needs_no_model_call(sv, tmp_path):
    sv.run_audit()
    assert sv.model_turns == [] and sv.mail == []
    assert [(v["verdict"], v["by"]) for v in verdicts(tmp_path)] == [("PASS", "rules")]


def test_periodic_report_calls_the_model(sv, tmp_path):
    swarm.update_state(lambda st: st.__setitem__("last_model_audit", (swarm.now() - timedelta(hours=5)).isoformat()))
    sv.run_audit()
    assert sv.model_turns == ["auditor"]


def test_killed_model_turn_leaves_the_rules_verdict(sv, tmp_path):
    sv.u = digest(calls(model="openai/gpt-x"))
    sv.run_audit()
    assert sv.model_turns == ["auditor"]
    assert all("no verdict" not in v["reason"] for v in verdicts(tmp_path))
    assert swarm.load_state()["alert_streak"] == 1
    assert len(sv.mail) == 1 and sv.mail[0].startswith("AUDIT FAIL")


def test_model_may_escalate_but_not_lower(sv, tmp_path):
    sv.js = [{"bead": "sw-a", "status": "done", "finished": (swarm.now() - timedelta(hours=2)).isoformat()}]
    swarm.update_state(lambda st: st.__setitem__("last_model_audit", (swarm.now() - timedelta(hours=2)).isoformat()))
    sv.model_says = "PASS"
    sv.run_audit()
    assert swarm.load_state()["last_verdict"] == "WARN"  # the model's PASS is ignored
    assert "AUDIT WARN" in sv.mail[-1] and "selfcheck" in sv.mail[-1] and "no selfcheck needed" in sv.mail[-1]
    swarm.update_state(lambda st: st.__setitem__("last_model_audit", (swarm.now() - timedelta(hours=2)).isoformat()))
    sv.model_says = "FAIL"
    sv.run_audit()
    st = swarm.load_state()
    assert st["last_verdict"] == "FAIL" and st["alert_streak"] == 1
    assert sv.mail[-1].startswith("AUDIT FAIL")


def test_health_only_warn_is_not_mailed(sv, tmp_path):
    sv.u = digest(calls(n=20, limited=15))
    sv.run_audit()
    assert verdicts(tmp_path)[-1]["verdict"] == "WARN"
    assert sv.mail == [] and sv.model_turns == []


def test_two_fails_in_a_row_start_a_postmortem(sv, tmp_path):
    sv.u = digest(calls(cost=0.5))
    sv.run_audit()
    sv.run_audit()
    assert swarm.load_state()["alert_streak"] == 2
    assert len(sv.postmortems) == 1
