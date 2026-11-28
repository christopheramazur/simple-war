"""Turn time limits from the current cost of a call, and a journal note for killed turns (sw-0zi.5)."""

from __future__ import annotations

import sys
from datetime import datetime, timezone

import pytest

from hx import keystore, swarm

C = {"budgets": {"orchestrator": 20, "worker": 40, "default": 20, "slack": 1.3, "cap_factor": 2.0}}


def row(latency, status="success", caller="swarm-worker-sw-a", error=None):
    return {"caller": caller, "status": status, "latency_s": latency, "error": error}


def test_seconds_per_call_scales_median_by_rate_limited_share():
    rows = [row(10), row(20), row(30), row(40), row(50)] + [row(None, "failure", error="litellm.RateLimitError")] * 5
    assert swarm.seconds_per_call(rows) == pytest.approx(30 * 1.5)


def test_seconds_per_call_needs_evidence_and_ignores_other_callers():
    assert swarm.seconds_per_call([row(10)] * 4) is None
    assert swarm.seconds_per_call([row(500, caller="-")] * 10) is None


@pytest.mark.parametrize("per_call, expected", [
    (None, (3600, 20)),        # no evidence: the configured limit
    (13, (3600, 20)),          # fast gateway: 20 x 13 x 1.3 = 338 s, the floor wins
    (180, (4680, 20)),         # 20 x 180 x 1.3
    (400, (7200, 20)),         # capped at 2x
])
def test_turn_budget(per_call, expected):
    assert swarm.turn_budget(C, "orchestrator", 3600, per_call) == expected


def test_turn_budget_unknown_group_uses_default():
    assert swarm.turn_budget(C, "retro", 1800, 100)[1] == 20


LOG = (
    "\x1b[0m> build · nous/qwen4-max\x1b[0m\n"
    "Let me look.\n"
    "\x1b[0m$ \x1b[0mbd show sw-opt | head -90\n"
    "lots of output\n"
    "→ Read C:/w/src/sim/battle/combat_system.gd [limit=120]\n"
    "← Edit C:/w/src/sim/battle/combat_system.gd\n"
    "\x1b[0m$ \x1b[0mharness/bin/hx godot test --dir tests/sim\n"
)


def test_turn_stub_lists_last_actions_and_commits():
    stub = swarm.turn_stub(LOG, ["abc123 fix timers"], -9, 3600, datetime(2026, 11, 22, 1, 52, tzinfo=timezone.utc))
    assert stub.startswith("## 2026-11-22 11:52 AEST turn killed at its time limit after 60 min (supervisor note)")
    assert "`$ bd show sw-opt | head -90`" in stub
    assert "`→ Read C:/w/src/sim/battle/combat_system.gd [limit=120]`" in stub
    assert "`← Edit C:/w/src/sim/battle/combat_system.gd`" in stub
    assert stub.index("bd show") < stub.index("godot test")
    assert "- commits this turn: abc123 fix timers" in stub
    assert "Let me look" not in stub and "build" not in stub


def test_turn_stub_for_a_stopped_turn_without_actions():
    stub = swarm.turn_stub("thinking...\n", [], swarm.STOPPED, 125)
    assert "ended because the swarm stopped after 2 min" in stub
    assert "last actions: none recorded" in stub and "commits this turn: none" in stub


def test_killed_turn_writes_the_stub(tmp_path, monkeypatch):
    monkeypatch.setattr(swarm, "STATE", tmp_path / "state")
    monkeypatch.setattr(swarm, "DOCS", tmp_path / "docs")
    monkeypatch.setattr(swarm, "ensure_gateway", lambda: None)
    monkeypatch.setattr(swarm, "opencode_exe", lambda: sys.executable)
    monkeypatch.setattr(keystore, "get", lambda name: "k")
    monkeypatch.setattr(swarm, "update_state", lambda fn: {})
    monkeypatch.setattr(swarm, "git", lambda *a, **k: swarm.subprocess.CompletedProcess([], 0, "", ""))
    (tmp_path / "run").write_text("print('$ git status', flush=True)\nimport time\ntime.sleep(60)\n", encoding="utf-8")
    rc, _ = swarm.run_turn("orchestrator", "p", cwd=tmp_path, timeout=2)
    assert rc == -9
    journal = (tmp_path / "docs" / "journals" / "orchestrator.md").read_text(encoding="utf-8")
    assert "turn killed at its time limit" in journal and "`$ git status`" in journal
