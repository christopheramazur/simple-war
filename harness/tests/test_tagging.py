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
    assert acc["pairs"] == 1 and acc["insufficient_sample"] is True
    assert (acc["kind_agree"], acc["outcome_agree"], acc["complexity_within_1"]) == (1.0, 0.0, 1.0)
    assert [d["session"] for d in acc["disagreements"]] == ["s1"]


def test_partial_outcome_is_always_audited(env, monkeypatch):
    monkeypatch.setattr(tagging, "metrics", lambda con, sid: {
        "calls": 4, "minutes": 3, "tools": {}, "tool_calls": 0, "tool_errors": 0, "denied": 0, "interrupts": 0,
        "api_errors": 0, "compactions": 0, "prompts": 1, "tasks": []})
    part = '{"kind": "feature", "area": "x", "complexity": 2, "outcome": "partial", "confidence": 0.8}'
    rows = tagging.tag_session("s1", con=object(), tax={**TAX, "audit_share": 0.0},
                               delegate_run=lambda *a: Outcome(target="b", model="m", text=part),
                               audit_call=lambda *a: Reply(text=part))
    assert [r["role"] for r in rows] == ["tagger", "audit"]


def test_escalated_tagger_is_recorded_invalid(env, monkeypatch):
    monkeypatch.setattr(tagging, "metrics", lambda con, sid: {
        "calls": 0, "minutes": 0, "tools": {}, "tool_calls": 0, "tool_errors": 0, "denied": 0, "interrupts": 0,
        "api_errors": 0, "compactions": 0, "prompts": 0, "tasks": []})
    rows = tagging.tag_session("s1", con=object(), tax={**TAX, "audit_share": 0.0},
                               delegate_run=lambda *a: Outcome())
    assert rows[0]["valid"] is False and "escalated" in rows[0]["problem"]


def test_untagged_busy_flags_idle_sessions_without_a_tag(env):
    import duckdb
    from datetime import datetime, timedelta
    con = duckdb.connect()
    con.execute("CREATE TABLE call (session_id VARCHAR, ts TIMESTAMP)")
    old = datetime(2026, 1, 1)
    con.executemany("INSERT INTO call VALUES (?, ?)", [("busy", old)] * 30 + [("small", old)] * 3 + [("tagged", old)] * 30)
    tagging._write({"session_id": "tagged", "role": "tagger", "valid": True, "kind": "chat"})
    gap = tagging.untagged_busy(con, now=(old + timedelta(days=2)).timestamp())
    assert gap == [{"session": "busy", "calls": 30}]
    assert tagging.untagged_busy(con, now=(old + timedelta(hours=1)).timestamp()) == []  # still live


def test_worker_tag_session_job_puts_a_kind_tag_in_the_ledger(env, monkeypatch):
    """Entry point: the tag_session job (enqueued by every session_end) leaves a kind tag in the tag file."""
    from hx import delegate, ledger, worker
    assert "tag_session" in worker.FOLLOW_UPS
    monkeypatch.setattr(tagging, "metrics", lambda con, sid: {
        "calls": 4, "minutes": 3, "tools": {}, "tool_calls": 0, "tool_errors": 0, "denied": 0, "interrupts": 0,
        "api_errors": 0, "compactions": 0, "prompts": 1, "tasks": []})
    monkeypatch.setattr(ledger, "read_only", lambda: type("C", (), {"close": lambda self: None})())
    good = '{"kind": "feature", "area": "combat UI", "complexity": 2, "outcome": "completed", "confidence": 0.8}'
    monkeypatch.setattr(delegate, "run", lambda *a, **k: Outcome(target="b", model="bonsai/nothink", text=good))
    monkeypatch.setattr(tagging, "is_audited", lambda sid, share: False)
    out = worker.HANDLERS["tag_session"][0]({"session_id": "s1"})
    assert "feature/completed" in out
    assert ("s1", "tagger") in tagging.tagged_ids()
    assert [r["kind"] for r in tagging.read_rows()] == ["feature"]
