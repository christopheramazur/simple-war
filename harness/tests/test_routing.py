import tomllib

from hx.bench import SUITE_VERSION, routing
from hx.providers import Provider

ROSTER = {
    "bonsai": Provider(id="bonsai", name="B", kind="local"),
    "groq": Provider(id="groq", name="G", kind="api"),
    "claude-pro": Provider(id="claude-pro", name="P", kind="subscription"),
}
TARGETS = {
    "bonsai-nothink": {"provider": "bonsai", "route_model": "bonsai/nothink"},
    "groq-70b": {"provider": "groq", "route_model": "groq/l70"},
    "haiku": {"provider": "claude-pro", "route_model": "claude-haiku-5-5"},
}


def row(target, cls, size, passed, ctx=0, latency=1.0, level="L1"):
    return {"suite_version": SUITE_VERSION, "target": target, "task_class": cls, "size": size, "level": level,
            "passed": passed, "context_tokens": ctx, "latency_s": latency}


def by_key(routes):
    return {(r["task_class"], r["size"]): r for r in routes}


def test_cheapest_auto_tier_wins_even_if_pricier_is_better():
    rows = [row("bonsai-nothink", "csv", "s", p) for p in (True, True, True)] + \
           [row("haiku", "csv", "s", True)]
    r = by_key(routing.build(rows, TARGETS, ROSTER))[("csv", "s")]
    assert (r["verdict"], r["model"]) == ("auto", "bonsai/nothink")
    assert [c["target"] for c in r["candidates"]] == ["bonsai-nothink", "haiku"]


def test_auto_beats_cheaper_review():
    rows = [row("bonsai-nothink", "tbl", "l", p) for p in (True, True, True, False)] + \
           [row("groq-70b", "tbl", "l", True)]
    r = by_key(routing.build(rows, TARGETS, ROSTER))[("tbl", "l")]
    assert r["candidates"][0]["target"] == "groq-70b" and r["verdict"] == "auto"
    assert r["candidates"][1]["verdict"] == "review"  # 0.75


def test_nothing_passes_means_escalate():
    rows = [row("bonsai-nothink", "attacks", "l", False, level="L2")]
    r = by_key(routing.build(rows, TARGETS, ROSTER))[("attacks", "l")]
    assert r["verdict"] == "no" and r["model"] is None and r["target"] is None


def test_context_sweep_sets_max_ctx_but_not_base_rate():
    rows = [row("bonsai-nothink", "log", "s", True),
            row("bonsai-nothink", "log", "s", True, ctx=32000),
            row("bonsai-nothink", "log", "s", False, ctx=96000)]
    c = by_key(routing.build(rows, TARGETS, ROSTER))[("log", "s")]["candidates"][0]
    assert c["pass_rate"] == 1.0 and c["n"] == 1 and c["max_ctx_passed"] == 32000


def test_ignores_other_suites_and_unknown_targets():
    rows = [row("bonsai-nothink", "csv", "s", True), {**row("bonsai-nothink", "csv", "s", False), "suite_version": "0"},
            row("mystery", "csv", "s", False)]
    r = by_key(routing.build(rows, TARGETS, ROSTER))[("csv", "s")]
    assert r["candidates"][0]["pass_rate"] == 1.0 and len(r["candidates"]) == 1


def test_toml_round_trips():
    rows = [row("bonsai-nothink", "csv", "s", True), row("haiku", "csv", "s", True, latency=2.5)]
    text = routing.to_toml(routing.build(rows, TARGETS, ROSTER), 'note with "quotes"')
    d = tomllib.loads(text)
    r = d["route"]["L1/csv/s"]
    assert d["suite_version"] == SUITE_VERSION and r["model"] == "bonsai/nothink"
    assert r["candidates"][1]["model"] == "claude-haiku-5-5" and r["candidates"][1]["p50_s"] == 2.5
