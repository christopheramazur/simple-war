import json
from datetime import datetime, timedelta, timezone

import pytest

from hx import ledger, reflection
from hx.bench.adapters import Reply

EV = {"window": "x", "delegate": {}, "failing_tools": [], "spend": []}


def prop(**over):
    return {"title": "Teach agents the PowerShell-safe verbs", "area": "prompts", "evidence": ["failing_tools"],
            "why": "w", "change": "c", "verify": "v", **over}


def test_probe_rules():
    out = reflection.probe([
        prop(),
        prop(title="Cite nothing", evidence=["made_up"]),
        prop(title="Nested cite ok", evidence=["delegate.fallback_reasons"]),
        prop(title="Raise the gemini budget to $5 a month"),
        prop(title="Seed verbs hx task adapter over bd"),
    ], EV, ["Seed verbs: hx task adapter over bd, hx godot check/test"])
    assert [p["rejected"] is None for p in out] == [True, False, True, False, False]
    assert out[4]["rejected"].startswith("duplicates open task")
    assert reflection.probe([prop(change="Do not raise the budgets; refusals are correct")], EV, [])[0]["rejected"] is None
    assert "area" in reflection.probe([prop(area="marketing")], EV, [])[0]["rejected"]
    assert len(reflection.probe([prop()] * 9, EV, [])) == reflection.MAX_PROPOSALS


def test_parse_tolerates_noise():
    assert reflection.parse('Sure! {"proposals": [{"title": "t"}]} done') == [{"title": "t"}]
    assert reflection.parse("no json") == []


@pytest.fixture
def con(tmp_path, monkeypatch):
    monkeypatch.setenv("HX_DATA_DIR", str(tmp_path))
    c = ledger.connect(tmp_path / "l.duckdb")
    yield c
    c.close()


def test_run_files_survivors_and_throttles(con):
    filed = []
    reply = Reply(text=json.dumps({"proposals": [prop(), prop(title="No evidence", evidence=[])]}))
    t0 = datetime(2026, 11, 1, tzinfo=timezone.utc)
    out = reflection.run(con, call=lambda *a: reply, create=lambda p: filed.append(p["title"]) or "sw-9",
                         titles=[], now=t0)
    assert filed == ["Teach agents the PowerShell-safe verbs"]
    assert [p["issue"] for p in out["proposals"]] == ["sw-9", None]
    assert "spend" in out["evidence"] and "delegate" in out["evidence"]
    assert reflection.run(con, call=None, titles=[], now=t0 + timedelta(days=2))["skipped"]
    assert len(list(reflection.out_dir().glob("*.json"))) == 1


def test_model_error_files_nothing(con):
    out = reflection.run(con, force=True, call=lambda *a: Reply(error="quota"), create=lambda p: 1 / 0, titles=[])
    assert out["proposals"] == [] and out["error"] == "quota"
