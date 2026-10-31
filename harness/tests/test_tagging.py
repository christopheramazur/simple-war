import json

import pytest

from hx import tagging
from hx.bench.adapters import Reply
from hx.delegate import Outcome

TAX = tagging.taxonomy()


@pytest.fixture
def env(tmp_path, monkeypatch):
    monkeypatch.setenv("HX_DATA_DIR", str(tmp_path))
    raw = tmp_path / "raw" / "claude-code" / "proj"
    raw.mkdir(parents=True)
    lines = [
        {"type": "user", "origin": {"kind": "human"}, "message": {"content": "Add a combat log panel"}},
        {"type": "user", "isMeta": True, "origin": {"kind": "human"}, "message": {"content": "<meta>"}},
        {"type": "assistant", "message": {"content": [{"type": "text", "text": "Done: panel added."}]}},
    ]
    (raw / "s1.jsonl").write_text("\n".join(json.dumps(x) for x in lines))


def test_parse_validates_against_taxonomy():
    tag, problem = tagging.parse('noise {"kind": "Feature", "area": "ui", "complexity": "3", '
                                 '"outcome": "completed", "confidence": 1.4} tail', TAX)
    assert problem is None and tag["kind"] == "feature" and tag["complexity"] == 3 and tag["confidence"] == 1.0
    assert tagging.parse('{"kind": "poetry", "outcome": "completed"}', TAX)[1].startswith("kind")
    assert tagging.parse("no json", TAX)[1] == "no JSON object"


def test_friction_is_computed():
    m = {"tool_calls": 10, "tool_errors": 2, "denied": 1, "interrupts": 1, "api_errors": 0, "compactions": 0}
    assert tagging.friction(m)["score"] == pytest.approx(0.4)


def test_audit_pick_is_deterministic_and_near_share():
    ids = [f"s{i}" for i in range(2000)]
    picked = [s for s in ids if tagging.is_audited(s, 0.10)]
    assert picked == [s for s in ids if tagging.is_audited(s, 0.10)]
    assert 150 < len(picked) < 250


def test_digest_uses_human_prompts_and_reply(env, tmp_path):
    f = tmp_path / "raw" / "claude-code" / "proj" / "s1.jsonl"
    assert tagging.human_prompts(f) == ["Add a combat log panel"]
    m = {"minutes": 3, "calls": 4, "tools": {"Edit": 2}, "tool_errors": 0, "interrupts": 0, "tasks": []}
    d = tagging.digest(tagging.human_prompts(f), m, tagging.last_reply(f))
    assert "combat log panel" in d and "Done: panel added." in d and "<meta>" not in d


def test_tag_session_writes_tagger_and_audit(env, monkeypatch):
    monkeypatch.setattr(tagging, "metrics", lambda con, sid: {
        "calls": 4, "minutes": 3, "tools": {}, "tool_calls": 0, "tool_errors": 0, "denied": 0, "interrupts": 0,
        "api_errors": 0, "compactions": 0, "prompts": 1, "tasks": []})
    good = '{"kind": "feature", "area": "combat UI", "complexity": 2, "outcome": "completed", "confidence": 0.8}'
    tax = {**TAX, "audit_share": 1.0}
    rows = tagging.tag_session("s1", con=object(), tax=tax,
                               delegate_run=lambda *a: Outcome(target="b", model="bonsai/nothink", text=good),
                               audit_call=lambda *a: Reply(text=good.replace("completed", "partial")))
    assert [r["role"] for r in rows] == ["tagger", "audit"] and all(r["valid"] for r in rows)
    assert tagging.tagged_ids() == {("s1", "tagger"), ("s1", "audit")}
    assert tagging.tag_session("s1", con=object(), tax=tax, delegate_run=None, audit_call=None) == []  # done
    acc = tagging.accuracy(tagging.read_rows())
    assert acc == {"pairs": 1, "kind_agree": 1.0, "outcome_agree": 0.0, "complexity_within_1": 1.0}


def test_escalated_tagger_is_recorded_invalid(env, monkeypatch):
    monkeypatch.setattr(tagging, "metrics", lambda con, sid: {
        "calls": 0, "minutes": 0, "tools": {}, "tool_calls": 0, "tool_errors": 0, "denied": 0, "interrupts": 0,
        "api_errors": 0, "compactions": 0, "prompts": 0, "tasks": []})
    rows = tagging.tag_session("s1", con=object(), tax={**TAX, "audit_share": 0.0},
                               delegate_run=lambda *a: Outcome())
    assert rows[0]["valid"] is False and "escalated" in rows[0]["problem"]
