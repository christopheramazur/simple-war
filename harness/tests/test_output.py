import json

from hx.output import FAIL, OK, WARN, Check, Result


def make():
    return Result("x", {"a": 1, "b": []}, [Check("good", OK), Check("meh", WARN, "hmm")])


def test_compact_hides_passing_checks():
    text = make().to_text()
    assert "good" not in text
    assert "[WARN] meh: hmm" in text
    assert "checks: 1/2 ok" in text
    assert "b: -" in text


def test_verbose_shows_passing_checks():
    assert "[ok] good" in make().to_text(verbose=True)


def test_exit_code_only_fails_on_fail():
    r = make()
    assert r.exit_code == 0
    r.checks.append(Check("bad", FAIL))
    assert r.exit_code == 1


def test_json_shape():
    d = json.loads(make().to_json())
    assert d["verb"] == "x" and d["ok"] is True
    assert d["checks"][1] == {"name": "meh", "status": "warn", "detail": "hmm"}
