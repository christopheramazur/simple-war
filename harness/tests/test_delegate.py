import io
import json

import pytest

from hx import delegate
from hx.bench.adapters import Reply
from hx.commands import mcp
from hx.providers import Provider

ROSTER = {
    "bonsai": Provider(id="bonsai", name="B", kind="local"),
    "groq": Provider(id="groq", name="G", kind="api"),
    "claude-pro": Provider(id="claude-pro", name="P", kind="subscription"),
    "mistral": Provider(id="mistral", name="M", kind="api", enabled=False),
}


def cand(target, model, provider, verdict="auto", tier=0, p50=1.0):
    return {"target": target, "model": model, "provider": provider, "verdict": verdict, "tier": tier,
            "pass_rate": 1.0 if verdict == "auto" else 0.8, "p50_s": p50}


TABLE = {"route": {
    "L1/csv/s": {"level": "L1", "candidates": [cand("bonsai-nothink", "bonsai/nothink", "bonsai"),
                                               cand("haiku", "claude-haiku-5-5", "claude-pro", tier=2)]},
    "L1/csv/l": {"level": "L1", "candidates": [cand("haiku", "claude-haiku-5-5", "claude-pro", tier=2),
                                               cand("bonsai-nothink", "bonsai/nothink", "bonsai", "no")]},
    "L1/tbl/m": {"level": "L1", "candidates": [cand("groq", "groq/x", "groq", "review", tier=1)]},
    "L2/att/m": {"level": "L2", "candidates": [cand("bonsai-nothink", "bonsai/nothink", "bonsai", "no")]},
}}


@pytest.fixture(autouse=True)
def tmp_data(tmp_path, monkeypatch):
    monkeypatch.setenv("HX_DATA_DIR", str(tmp_path))
    monkeypatch.setattr(delegate, "_ready", lambda c, roster, start: None if roster[c["provider"]].enabled else "disabled")


def test_lookup_exact_larger_size_and_level():
    assert delegate.lookup(TABLE, "L1", "csv", "s")[:2] == ("L1/csv/s", "exact")
    key, match, cands = delegate.lookup(TABLE, "L1", "csv", "m")
    assert (key, match, cands[0]["target"]) == ("L1/csv/l", "larger-size", "haiku")
    # unknown class falls back level-wide; no target is auto on every L1 route here

    assert delegate.lookup(TABLE, "L1", "unknown", "s") == (None, "none", [])
    assert delegate.lookup(TABLE, "L2", "att", "m") == (None, "none", [])


def test_level_wide_needs_auto_everywhere():
    t = {"route": {"L3/a/s": {"level": "L3", "candidates": [cand("b", "bm", "bonsai"), cand("h", "hm", "claude-pro", tier=2)]},
                   "L3/b/s": {"level": "L3", "candidates": [cand("h", "hm", "claude-pro", tier=2), cand("b", "bm", "bonsai", "review")]}}}
    key, match, cands = delegate.lookup(t, "L3", None, "s")
    assert (key, match, [c["target"] for c in cands]) == ("L3/*", "level", ["h"])


def test_falls_back_on_error_and_flags_review():
    calls = []

    def fake(target, system, prompt, timeout):
        calls.append(target["model"])
        return Reply(error="HTTPError 429") if target["model"] == "bonsai/nothink" else Reply(text="ok", output_tokens=3)
    out = delegate.run("x", "L1", "csv", "s", table=TABLE, roster=ROSTER, call=fake)
    assert calls == ["bonsai/nothink", "claude-haiku-5-5"]
    assert (out.target, out.text, out.escalate, out.needs_review) == ("haiku", "ok", False, False)
    assert out.tried[0]["error"].startswith("HTTPError")
    out = delegate.run("x", "L1", "tbl", "m", table=TABLE, roster=ROSTER, call=lambda *a: Reply(text="t"))
    assert out.needs_review and out.verdict == "review"


def test_subscription_uses_claude_cli_others_gateway():
    seen = []
    delegate.run("x", "L1", "csv", "s", table=TABLE, roster=ROSTER,
                 call=lambda t, *a: seen.append(t) or Reply(error="boom"))
    assert seen[0]["adapter"] == "openai" and seen[0]["base_url"].endswith(":4000/v1")
    assert seen[1] == {"adapter": "claude-cli", "model": "claude-haiku-5-5"}


def test_escalate_is_logged(tmp_path):
    out = delegate.run("x", "L2", "att", "m", table=TABLE, roster=ROSTER, call=lambda *a: Reply(text="never"))
    assert out.escalate
    rows = [json.loads(line) for f in (tmp_path / "raw" / "delegate").glob("*.jsonl") for line in f.read_text().splitlines()]
    assert rows[-1]["escalate"] is True and "prompt" not in rows[-1]


def _rate_limited(**kw):
    return Reply(error="HTTPError: HTTP Error 429", status=429, **kw)


def test_429_retried_honouring_retry_after(monkeypatch):
    sleeps, calls = [], []
    monkeypatch.setattr(delegate.time, "sleep", sleeps.append)

    def fake(target, system, prompt, timeout):
        calls.append((target["model"], target["retries"]))
        if target["model"] == "bonsai/nothink" and len(calls) < 3:
            return _rate_limited(retry_after=2.0)
        return Reply(text="ok", output_tokens=3)
    out = delegate.run("x", "L1", "csv", "s", table=TABLE, roster=ROSTER, call=fake)
    assert sleeps == [2.0, 2.0]  # Retry-After honoured on each retry
    assert [m for m, _ in calls] == ["bonsai/nothink"] * 3  # third try succeeds: no fall-through to haiku
    assert all(r == 0 for _, r in calls)  # the adapter's own retry loop is off: delegate owns the policy
    assert (out.target, out.escalate) == ("bonsai-nothink", False)


def test_429_backoff_when_no_retry_after_then_next_candidate(monkeypatch):
    sleeps, calls = [], []
    monkeypatch.setattr(delegate.time, "sleep", sleeps.append)
    fake = lambda t, *a: calls.append(t["model"]) or (_rate_limited() if t["model"] == "bonsai/nothink" else Reply(text="ok"))
    out = delegate.run("x", "L1", "csv", "s", table=TABLE, roster=ROSTER, call=fake)
    assert sleeps == [2.0, 5.0, 10.0]  # RETRIES_429 retries with backoff, then the next candidate
    assert calls == ["bonsai/nothink"] * 4 + ["claude-haiku-5-5"] and out.target == "haiku"


def test_429_wait_capped_by_timeout(monkeypatch):
    sleeps = []
    monkeypatch.setattr(delegate.time, "sleep", sleeps.append)
    fake = lambda t, *a: _rate_limited(retry_after=60.0) if t["model"] == "bonsai/nothink" else Reply(text="ok")
    out = delegate.run("x", "L1", "csv", "s", table=TABLE, roster=ROSTER, timeout=30, call=fake)
    assert sleeps == [] and out.target == "haiku"  # a 60 s wait doesn't fit in 30 s: move on at once


def test_gate_budget_refusal_not_retried(monkeypatch):
    sleeps, calls = [], []
    monkeypatch.setattr(delegate.time, "sleep", sleeps.append)

    def fake(t, *a):
        calls.append(t["model"])
        if t["model"] == "bonsai/nothink":
            return _rate_limited(body="bonsai: monthly budget $5 spent ($5.01); raising it needs the user's approval")
        return Reply(text="ok")
    out = delegate.run("x", "L1", "csv", "s", table=TABLE, roster=ROSTER, call=fake)
    assert sleeps == [] and calls == ["bonsai/nothink", "claude-haiku-5-5"] and out.target == "haiku"


def test_adapter_call_maps_http_429(monkeypatch):
    import email.message
    import io
    import urllib.error
    import urllib.request

    from hx.bench import adapters

    calls = []

    def urlopen_429(req, timeout=None):
        calls.append(req)
        hdrs = email.message.Message()
        hdrs["Retry-After"] = "3"
        raise urllib.error.HTTPError("http://x", 429, "Too Many", hdrs, io.BytesIO(b'{"error": "slow down"}'))
    monkeypatch.setattr(urllib.request, "urlopen", urlopen_429)
    target = {"adapter": "openai", "base_url": "http://x", "model": "m", "retries": 0}
    r = adapters.call(target, "s", "p", 5)
    assert len(calls) == 1  # retries=0: the adapter makes one attempt; delegate decides the rest
    assert (r.status, r.retry_after, r.error[:10], "slow down" in r.body) == (429, 3.0, "HTTPError:", True)


def test_guess_size():
    assert [delegate.guess_size("a" * n) for n in (100, 2000, 8000)] == ["s", "m", "l"]


def test_mcp_protocol(monkeypatch, capsys):
    monkeypatch.setattr(delegate, "run", lambda *a, **k: delegate.Outcome(route="L1/csv/s", target="b", model="m", text="RESULT"))
    msgs = [{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}},
            {"jsonrpc": "2.0", "method": "notifications/initialized"},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
            {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "delegate", "arguments": {"prompt": "p", "level": "L1"}}},
            {"jsonrpc": "2.0", "id": 4, "method": "nope"}]
    monkeypatch.setattr("sys.stdin", io.StringIO("\n".join(json.dumps(m) for m in msgs) + "\n"))
    mcp.run(None)
    out = [json.loads(line) for line in capsys.readouterr().out.splitlines()]
    assert [o["id"] for o in out] == [1, 2, 3, 4]
    assert out[1]["result"]["tools"][0]["name"] == "delegate"
    assert out[2]["result"]["content"][0]["text"] == "RESULT"
    assert out[3]["error"]["code"] == -32601


def test_provider_checked_once_per_call(monkeypatch):
    checks = []
    monkeypatch.setattr(delegate, "_ready", lambda c, roster, start: checks.append(c["target"]) or "no VRAM")
    t = {"route": {"L1/x/s": {"level": "L1", "candidates": [cand("b1", "bonsai/nothink", "bonsai"),
                                                             cand("b2", "bonsai/think", "bonsai")]}}}
    out = delegate.run("x", "L1", "x", "s", table=t, roster=ROSTER, call=lambda *a: Reply(text="never"))
    assert checks == ["b1"] and [x["skipped"] for x in out.tried] == ["no VRAM"]  # one reason per provider per call


def test_model_pin_filters_or_finds_route():
    key, match, cands = delegate.lookup(TABLE, "L1", "csv", "s")
    assert delegate.pin(TABLE, cands, key, match, "L1", "claude-haiku-5-5")[2][0]["target"] == "haiku"
    # not on the looked-up route: taken from another route of the level
    assert delegate.pin(TABLE, cands, key, match, "L1", "groq/x")[:2] == ("L1/tbl/m", "pinned")
    # falls back to any level; a model with no usable entry anywhere escalates
    assert delegate.pin(TABLE, [], None, "none", "L2", "bonsai/nothink")[:2] == ("L1/csv/s", "pinned")
    assert delegate.pin(TABLE, [], None, "none", "L1", "nope") == (None, "none", [])
    calls = []
    out = delegate.run("x", "L1", "csv", "s", table=TABLE, roster=ROSTER, model="claude-haiku-5-5",
                       call=lambda t, *a: calls.append(t["model"]) or Reply(text="ok"))
    assert calls == ["claude-haiku-5-5"] and out.target == "haiku"
