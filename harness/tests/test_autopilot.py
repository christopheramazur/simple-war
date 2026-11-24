"""hx autopilot: plan-limit gating, the headless session, and what happens to a bead after it."""

from __future__ import annotations

import json
import subprocess
import sys
import textwrap
from pathlib import Path

import pytest

from hx import autopilot as ap
from hx import quota

H = 3600
C = {"claude": {"model": "sonnet", "permission_mode": "auto", "max_turns": 50, "timeout_s": 60},
     "limits": {"five_hour_start_pct": 60, "five_hour_stop_pct": 85, "weekly_max_pct": 75, "weekly_slack_pct": 10,
                "reading_max_age_s": 900},
     "beads": {"max_attempts": 2, "exclude_labels": ["needs-human", "autopilot-failed", "autopilot-blocked"],
               "exclude_parents": ["sw-p2q"], "idle_s": 900},
     "merge": {"test_timeout_s": 60}}
T = 1_800_000_000.0


def snap(window, pct, resets_in, age=0.0):
    return quota.Snapshot(ts=T - age, window=window, used_pct=pct, resets_at=T + resets_in)


def both(five=10, week=10, five_reset=3 * H, week_reset=5 * 24 * H, age=0.0):
    return {"five_hour": snap("five_hour", five, five_reset, age), "seven_day": snap("seven_day", week, week_reset, age)}


# ---------------------------------------------------------------- limits

def test_weekly_pace_line():
    lim = C["limits"]
    assert ap.weekly_cap(lim, T + ap.WEEK, T) == 10           # week just started: only the slack
    assert ap.weekly_cap(lim, T + ap.WEEK / 2, T) == pytest.approx(47.5)
    assert ap.weekly_cap(lim, T + 60, T) == 75                 # never past the weekly maximum
    t = ap.weekly_unblock(lim, 47.5, T + ap.WEEK / 2)
    assert t == pytest.approx(T)
    assert ap.weekly_unblock(lim, 80, T + 3 * H) == T + 3 * H  # at the maximum: wait for the reset


def test_gate_goes_under_both_caps():
    assert ap.gate(C, both(), T)[0] == "go"


@pytest.mark.parametrize("latest", [{}, both(age=1000), {"five_hour": snap("five_hour", 1, H)}])
def test_gate_probes_without_fresh_readings(latest):
    assert ap.gate(C, latest, T)[0] == "probe"


def test_gate_waits_for_the_five_hour_reset():
    d, why, until = ap.gate(C, both(five=60), T)
    assert d == "wait" and "5-hour" in why and until == T + 3 * H


def test_a_window_that_reset_since_the_reading_is_empty():
    assert ap.gate(C, both(five=95, five_reset=-60, age=100), T)[0] == "go"


def test_gate_waits_for_the_weekly_pace():
    d, why, until = ap.gate(C, both(week=40, week_reset=5 * 24 * H), T)  # 2/7 of the week gone: cap 31%
    assert d == "wait" and "weekly" in why
    assert T < until < T + 5 * 24 * H


EVENT = {"type": "rate_limit_event", "rate_limit_info": {"status": "allowed", "unifiedWindows": {
    "five_hour": {"utilization": 0.42, "resetsAt": 1795354200, "status": "allowed"},
    "seven_day": {"utilization": 0.1, "resetsAt": 1795820400, "status": "allowed"}}}}


def test_snapshots_from_a_rate_limit_event():
    s = {x.window: x for x in ap.snapshots_from(EVENT, T)}
    assert s["five_hour"].used_pct == 42.0 and s["seven_day"].resets_at == 1795820400
    assert not ap.limit_hit(EVENT)
    spent = json.loads(json.dumps(EVENT))
    spent["rate_limit_info"]["unifiedWindows"]["five_hour"]["status"] = "rejected"
    assert ap.limit_hit(spent)


@pytest.mark.parametrize("text, result, summary", [
    ("work...\nRESULT: done - fixed the card; godot test green", "done", "fixed the card; godot test green"),
    ("**RESULT:** partial — tests left", "partial", "tests left"),
    ("RESULT: partial - x\nmore\nRESULT: blocked - needs the user", "blocked", "needs the user"),
])
def test_result_line(text, result, summary):
    m = list(ap.RESULT.finditer(text))[-1]
    assert (m.group(1).lower(), m.group(2).strip()) == (result, summary)


def test_never_bypass_permissions():
    with pytest.raises(ValueError):
        ap.claude_cmd({**C["claude"], "permission_mode": "bypassPermissions"})


# ---------------------------------------------------------------- the headless session

@pytest.fixture
def env(tmp_path, monkeypatch):
    monkeypatch.setattr(ap, "STATE", tmp_path / "state")
    monkeypatch.setattr(quota, "log_path", lambda provider="claude-pro": tmp_path / "quota.jsonl")
    return tmp_path


def fake_claude(monkeypatch, tmp_path, lines, sleep=0.0):
    script = tmp_path / "fake_claude.py"
    script.write_text(textwrap.dedent(f"""
        import json, sys, time
        sys.stdin.read()
        for o in {lines!r}:
            print(json.dumps(o), flush=True)
            time.sleep({sleep})
        time.sleep({sleep} * 20)
    """), encoding="utf-8")
    monkeypatch.setattr(ap, "claude_cmd", lambda cl: [sys.executable, str(script)])


def test_session_reads_result_and_records_limits(env, monkeypatch):
    fake_claude(monkeypatch, env, [EVENT, {"type": "result", "num_turns": 7, "total_cost_usd": 0.5,
                                           "result": "Done.\nRESULT: done - fixed it"}])
    out = ap.run_claude(C, "p", env, env / "log.jsonl", lambda: False)
    assert out["end"] == "exit" and out["rc"] == 0
    assert (out["result"], out["summary"], out["turns"]) == ("done", "fixed it", 7)
    assert {s.window for s in quota.read_tail(env / "quota.jsonl")} == {"five_hour", "seven_day"}
    assert (env / "log.prompt.md").read_text(encoding="utf-8") == "p"


def test_session_ends_when_the_five_hour_window_passes_the_stop_line(env, monkeypatch):
    hot = json.loads(json.dumps(EVENT))
    hot["rate_limit_info"]["unifiedWindows"]["five_hour"]["utilization"] = 0.9
    fake_claude(monkeypatch, env, [hot, {"type": "assistant"}], sleep=1.0)
    out = ap.run_claude(C, "p", env, env / "log.jsonl", lambda: False)
    assert out["end"] == ap.LIMITED and out["result"] is None


def test_session_ends_on_stop(env, monkeypatch):
    fake_claude(monkeypatch, env, [{"type": "assistant"}], sleep=1.0)
    assert ap.run_claude(C, "p", env, env / "log.jsonl", lambda: True)["end"] == ap.STOPPED


# ---------------------------------------------------------------- after the session

@pytest.fixture
def bead(env, monkeypatch):
    calls, merges = [], []
    st = {"session": {"end": "exit", "rc": 0, "result": "done", "summary": "fixed", "turns": 9, "cost_usd": 1.0},
          "commits": "2", "merge_error": None}
    monkeypatch.setattr(ap.swarm, "_bd", lambda *a: calls.append(a) or subprocess.CompletedProcess(a, 0, "bead text", ""))
    monkeypatch.setattr(ap, "prepare_worktree", lambda b: (env, f"autopilot/{b}", False))
    monkeypatch.setattr(ap, "run_claude", lambda *a, **k: dict(st["session"]))
    monkeypatch.setattr(ap, "save_wip", lambda *a: False)
    monkeypatch.setattr(ap, "git", lambda *a, **k: subprocess.CompletedProcess(a, 0, st["commits"] + "\n", ""))

    def merge(branch, wt, timeout, protected):
        if st["merge_error"]:
            raise ValueError(st["merge_error"])
        merges.append(branch)
        return ["godot check", "godot test"], ""
    monkeypatch.setattr(ap.swarm, "merge_branch", merge)
    return {"calls": calls, "merges": merges, "st": st}


def labels(calls):
    return [c[2] for c in calls if c[0] == "update" and c[2].startswith("--add-label")]


def test_done_merges_and_closes(bead):
    j = ap.run_bead(C, {"id": "sw-x"})
    assert j["outcome"] == "merged" and bead["merges"] == ["autopilot/sw-x"]
    assert ("update", "sw-x", "--claim") in bead["calls"]
    close = [c for c in bead["calls"] if c[0] == "close"]
    assert close and "godot test" in close[0][2]
    assert not [c for c in bead["calls"] if c[0] == "unclaim"]


def test_failed_merge_returns_the_bead(bead):
    bead["st"]["merge_error"] = "tests failed on the merged branch (godot test)"
    j = ap.run_bead(C, {"id": "sw-x"})
    assert j["outcome"] == "merge_failed" and "godot test" in j["detail"]
    assert ("unclaim", "sw-x") in bead["calls"] and labels(bead["calls"]) == []
    j = ap.run_bead(C, {"id": "sw-x"})  # second attempt fails too: left for a person
    assert labels(bead["calls"]) == ["--add-label=autopilot-failed"] and j["attempts"] == 2


def test_blocked_is_labelled(bead):
    bead["st"]["session"].update(result="blocked", summary="needs a design call")
    bead["st"]["commits"] = "0"
    j = ap.run_bead(C, {"id": "sw-x"})
    assert j["outcome"] == "blocked" and labels(bead["calls"]) == ["--add-label=autopilot-blocked"]


def test_blocked_work_is_merged_and_labelled(bead):
    bead["st"]["session"].update(result="blocked", summary="needs a design call")
    j = ap.run_bead(C, {"id": "sw-x"})
    assert j["outcome"] == "merged_blocked" and bead["merges"] == ["autopilot/sw-x"]
    assert labels(bead["calls"]) == ["--add-label=autopilot-blocked"]
    assert not [c for c in bead["calls"] if c[0] == "close"]


def test_partial_work_is_merged_and_the_bead_left_open(bead):
    bead["st"]["session"].update(result="partial", summary="the setting waits on sw-y")
    j = ap.run_bead(C, {"id": "sw-x"})
    assert j["outcome"] == "merged_partial" and bead["merges"] == ["autopilot/sw-x"]
    assert ("unclaim", "sw-x") in bead["calls"] and labels(bead["calls"]) == ["--add-label=autopilot-partial"]
    assert not [c for c in bead["calls"] if c[0] == "close"]


def test_partial_that_fails_the_gate_stays_on_its_branch(bead):
    bead["st"]["session"].update(result="partial", summary="half")
    bead["st"]["merge_error"] = "tests failed on the merged branch (godot test)"
    j = ap.run_bead(C, {"id": "sw-x"})
    assert j["outcome"] == "merge_failed" and labels(bead["calls"]) == []


def test_done_without_commits_is_not_merged(bead):
    bead["st"]["commits"] = "0"
    assert ap.run_bead(C, {"id": "sw-x"})["outcome"] == "no_commits" and bead["merges"] == []


def test_a_limit_cut_does_not_use_up_an_attempt(bead):
    bead["st"]["session"].update(end=ap.LIMITED, result=None, rc=1)
    j = ap.run_bead(C, {"id": "sw-x"})
    assert j["outcome"] == ap.LIMITED and j["attempts"] == 0 and ("unclaim", "sw-x") in bead["calls"]


def test_claim_failure_skips(bead, monkeypatch):
    monkeypatch.setattr(ap.swarm, "_bd", lambda *a: subprocess.CompletedProcess(a, 1, "", "already claimed"))
    assert ap.run_bead(C, {"id": "sw-x"})["outcome"] == "claim_failed"


# ---------------------------------------------------------------- picking and the loop

def b(id, labels=None, parent=None, priority=2):
    return {"id": id, "priority": priority, "issue_type": "task", "labels": labels, "parent": parent, "title": "t",
            "description": "", "created_at": "2026-11-01"}


def test_pick_skips_exclusions_tried_beads_and_swarm_paths(env, monkeypatch):
    ready = [b("sw-fail", ["autopilot-failed"], priority=0), b("sw-int", parent="sw-p2q", priority=0),
             b("sw-tried", priority=0), {**b("sw-swarm", priority=0), "description": "edit src/ui/card.gd"}, b("sw-ok")]
    monkeypatch.setattr(ap.swarm, "_bd_json", lambda *a: ready)
    monkeypatch.setattr(ap.swarm, "jobs", lambda: [{"status": "running", "bead_text": "worker on src/ui"}])
    ap.save_job({"bead": "sw-tried", "attempts": 2})
    assert ap.pick(C, set())["id"] == "sw-ok"


def test_pick_keeps_to_include_labels(env, monkeypatch):
    ready = [b("sw-other", priority=0), b("sw-u1", ["u1", "u1-orders"], priority=2)]
    monkeypatch.setattr(ap.swarm, "_bd_json", lambda *a: ready)
    monkeypatch.setattr(ap.swarm, "jobs", lambda: [])
    focus = {**C, "beads": {**C["beads"], "include_labels": ["u1"]}}
    assert ap.pick(focus, set())["id"] == "sw-u1"
    assert ap.pick(C, set())["id"] == "sw-other"


def test_loop_waits_instead_of_starting(env, monkeypatch):
    monkeypatch.setattr(ap, "cfg", lambda: C)
    monkeypatch.setattr(ap, "readings", lambda: both(five=70))
    monkeypatch.setattr(ap, "run_bead", lambda *a, **k: pytest.fail("started a bead over the limit"))
    assert ap.run_loop(once=True) == []
    assert ap.events()[-1]["kind"] == "wait"


def test_loop_runs_one_bead(env, monkeypatch):
    monkeypatch.setattr(ap, "cfg", lambda: C)
    monkeypatch.setattr(ap, "readings", lambda: both(week=0))  # the loop reads the real clock, not T
    monkeypatch.setattr(ap, "pick", lambda c, skip: b("sw-ok"))
    monkeypatch.setattr(ap, "run_bead", lambda c, bead, stop: {"bead": bead["id"], "outcome": "merged"})
    assert ap.run_loop(once=True) == [{"bead": "sw-ok", "outcome": "merged"}]


def test_stop_file_stops_the_loop(env, monkeypatch):
    monkeypatch.setattr(ap, "cfg", lambda: C)
    Path(ap.STATE).mkdir(parents=True)
    (ap.STATE / "STOP").write_text("x")
    assert ap.run_loop() == []


def test_godot_tooling_changes_run_the_godot_check():
    names = [" ".join(c[-2:]) for c in ap.swarm._checks_for(["harness/godot/native_method_lint.gd"])]
    assert "godot check" in names and "-q -x" in names
    assert "godot check" not in [" ".join(c[-2:]) for c in ap.swarm._checks_for(["harness/src/hx/report.py"])]


# ---------------------------------------------------------------- model tiers

TIERED = {**C, "claude": {**C["claude"], "model": "haiku", "effort": "high",
                          "large": {"model": "opus", "effort": "medium", "labels": ["large"], "min_description_chars": 50}}}


def test_tier_by_label_description_and_escalation():
    assert ap.tier(C, {"labels": ["large"]}, {}) == "default"  # no [claude.large]: one model for everything
    assert ap.tier(TIERED, {"description": "short"}, {}) == "default"
    assert ap.tier(TIERED, {"labels": ["large"]}, {}) == "large"
    assert ap.tier(TIERED, {"description": "x" * 50}, {}) == "large"
    assert ap.tier(TIERED, {}, {"tier": "large"}) == "large"


def test_session_cfg_and_effort_flag():
    cl = ap.session_cfg(TIERED, "large")["claude"]
    assert (cl["model"], cl["effort"], cl["max_turns"], "large" in cl) == ("opus", "medium", 50, False)
    cmd = ap.claude_cmd(ap.session_cfg(TIERED, "default")["claude"])
    assert cmd[cmd.index("--model") + 1] == "haiku" and cmd[cmd.index("--effort") + 1] == "high"
    assert "--effort" not in ap.claude_cmd(C["claude"])


def test_prompt_offers_escalation_only_to_the_small_model():
    small = ap.session_cfg(TIERED, "default")
    small["claude"]["tiered"] = True
    big = ap.session_cfg(TIERED, "large")
    big["claude"]["tiered"] = True
    assert "RESULT: escalate" in ap.prompt_for("sw-x", "", "b", Path("."), {}, small, "default")
    p = ap.prompt_for("sw-x", "", "b", Path("."), {}, big, "large")
    assert "RESULT: escalate" not in p and "subagents" in p
    assert "escalate" not in ap.prompt_for("sw-x", "", "b", Path("."), {}, C, "default")


def test_escalate_hands_the_bead_to_the_large_model_without_an_attempt(bead):
    bead["st"]["session"].update(result="escalate", summary="touches six systems")
    j = ap.run_bead(TIERED, {"id": "sw-x"})
    assert (j["outcome"], j["attempts"], j["tier"]) == ("escalated", 0, "large") and not bead["merges"]
    assert not labels(bead["calls"])
    bead["st"]["session"].update(result="done", summary="fixed")
    j = ap.run_bead(TIERED, {"id": "sw-x"})
    assert (j["outcome"], j["model"]) == ("merged", "opus")


def test_drain_finishes_the_running_bead_then_stops(env, monkeypatch):
    monkeypatch.setattr(ap, "cfg", lambda: C)
    monkeypatch.setattr(ap, "readings", lambda: both(week=0))
    monkeypatch.setattr(ap, "pick", lambda c, skip: b("sw-ok"))

    def run(c, bead, stop):
        assert not stop()  # the running bead is not cut off
        (ap.STATE / "DRAIN").write_text("x")  # `stop --after-bead` arrives mid-bead
        return {"bead": bead["id"], "outcome": "merged"}
    monkeypatch.setattr(ap, "run_bead", run)
    assert ap.run_loop() == [{"bead": "sw-ok", "outcome": "merged"}]  # one bead, then the loop ends
    assert not (ap.STATE / "DRAIN").exists()
