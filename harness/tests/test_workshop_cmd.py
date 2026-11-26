"""hx workshop against a canned --json report (data/sim/workshop/README.md, schema 1). No Godot needed."""

import json
from pathlib import Path

import pytest

from hx.cli import VERBS, build_parser, main
from hx.commands import godot as godot_cmd
from hx.commands import workshop

FIXTURE = Path(__file__).parent / "fixtures" / "workshop_report_v1.json"


def canned() -> dict:
    return json.loads(FIXTURE.read_text(encoding="utf-8"))


def stdout_of(report: dict) -> list[str]:
    """What workshop_cli prints: engine chatter, then the report between the markers on one line."""
    return ["Godot Engine v4.7.2-stable (official)", "WARNING: something harmless",
            "WORKSHOP_JSON_BEGIN", json.dumps(report), "WORKSHOP_JSON_END"]


def fake_godot(monkeypatch, lines: list[str], code: int = 0) -> list[list[str]]:
    """Replace the console lookup and the run; returns the Godot argument lists the verb passed."""
    calls: list[list[str]] = []
    monkeypatch.setattr(godot_cmd, "_console", lambda: (Path("/repo"), Path("godot.exe")))

    def fake_run(exe, root, args, timeout, headless=True):
        calls.append(list(args))
        return code, lines
    monkeypatch.setattr(godot_cmd, "_run", fake_run)
    return calls


def run_verb(argv: list[str]):
    args = build_parser().parse_args(["workshop", *argv])
    return args._mod.run(args)


def write_scenarios(repo: Path) -> Path:
    d = repo / "data" / "sim" / "workshop"
    d.mkdir(parents=True)
    for sid in ("rifle_vs_dummy", "rifles_kill_unarmed"):
        (d / f"{sid}.json").write_text(json.dumps({"id": sid, "component": "fire", "status": "gate",
                                                   "variants": {"run_away": {}}, "probes": [{"id": "x"}]}),
                                       encoding="utf-8")
    (d / "broken_file.json").write_text("{not json", encoding="utf-8")
    return d


def test_fixture_matches_schema_v1():
    rep = canned()
    assert rep["schema"] == 1
    scenario_keys = {"schema", "scenario", "path", "component", "status", "doc", "package", "data_hash",
                     "engine", "map", "open", "seed", "turns", "probe_stride", "result", "gate_failures",
                     "pending", "unexpected_passes", "errors", "variants", "compare"}
    variant_keys = {"name", "hash", "turn_hashes", "turns_run", "frames", "errors", "probes"}
    probe_keys = {"id", "kind", "squad", "target", "when", "value", "expect", "result", "error"}
    compare_keys = {"metric", "lhs", "rhs", "rel", "factor", "lhs_value", "rhs_value", "result"}
    for s in rep["scenarios"]:
        assert set(s) == scenario_keys
        assert s["result"] in ("pass", "fail", "error")
        for v in s["variants"]:
            assert set(v) == variant_keys
            assert all(set(p) == probe_keys for p in v["probes"])
        assert all(set(c) == compare_keys for c in s["compare"])


def test_text_is_one_line_per_scenario_failures_first(monkeypatch, fake_repo):
    write_scenarios(fake_repo)
    calls = fake_godot(monkeypatch, stdout_of(canned()))
    r = run_verb(["run", "--all"])
    lines = r.to_text().splitlines()
    assert calls[0][calls[0].index("--scenario") + 1] == "all"
    assert lines[0].startswith("ERROR broken_file [gate]")
    assert lines[1].startswith("    broken_file.json: squads[0].at")
    assert lines[2].startswith("FAIL rifles_kill_unarmed [gate] base ")
    assert lines[3] == '    FAIL base.kills (kills over all): 3 expect {"min":4}'
    # The passing scenario is one line, and its pending and compare lines stay hidden without --trace.
    assert lines[4].startswith("PASS rifle_vs_dummy [gate] base 1a2b3c4d gate_failures=0 pending=1")
    assert len(lines) == 5
    assert r.exit_code == 1


def test_trace_lists_passing_pending_and_compare(monkeypatch, fake_repo):
    write_scenarios(fake_repo)
    fake_godot(monkeypatch, stdout_of(canned()))
    lines = run_verb(["run", "--all", "--trace"]).to_text().splitlines()
    assert "    ok base.duty (duty over t1:0-t1:end): 0.1 expect {\"min\":0.09}" in lines
    assert "    pending base.spread (spacing at end): 1.5 expect 4" in lines
    assert "    ok compare duty: base 0.1 > 2.0 x run_away 0.03" in lines


def test_all_passing_is_one_line_per_scenario(monkeypatch, fake_repo):
    write_scenarios(fake_repo)
    rep = canned()
    rep["scenarios"] = [rep["scenarios"][0]]
    rep["ok"] = True
    fake_godot(monkeypatch, stdout_of(rep))
    r = run_verb(["run", "--all"])
    assert r.exit_code == 0
    assert r.to_text().splitlines() == [
        "PASS rifle_vs_dummy [gate] base 1a2b3c4d gate_failures=0 pending=1"]


def test_pending_only_never_fails(monkeypatch, fake_repo):
    write_scenarios(fake_repo)
    rep = canned()
    rep["scenarios"] = [rep["scenarios"][0]]
    fake_godot(monkeypatch, stdout_of(rep))
    assert run_verb(["run", "rifle_vs_dummy"]).exit_code == 0


def test_variant_and_id_are_passed_through(monkeypatch, fake_repo):
    write_scenarios(fake_repo)
    calls = fake_godot(monkeypatch, stdout_of(canned()))
    run_verb(["run", "rifle_vs_dummy", "--variant", "run_away"])
    args = calls[-1]
    assert args[args.index("--scenario") + 1] == "rifle_vs_dummy"
    assert args[args.index("--variant") + 1] == "run_away"
    assert args[-1] == "--json"
    assert args[:3] == ["-s", workshop.CLI, "--"]


def test_json_output_carries_the_report(monkeypatch, fake_repo, capsys):
    write_scenarios(fake_repo)
    fake_godot(monkeypatch, stdout_of(canned()))
    assert main(["workshop", "run", "--all", "--json"]) == 1
    d = json.loads(capsys.readouterr().out)
    assert d["verb"] == "workshop" and d["ok"] is False
    assert [s["scenario"] for s in d["data"]["scenarios"]] == ["broken_file", "rifles_kill_unarmed",
                                                              "rifle_vs_dummy"]


def test_missing_or_bad_report_is_a_failure(monkeypatch, fake_repo):
    write_scenarios(fake_repo)
    fake_godot(monkeypatch, ["SCRIPT ERROR: boom"], code=1)
    r = run_verb(["run", "--all"])
    assert r.exit_code == 1
    assert "no usable report (exit 1)" in r.checks[0].detail
    fake_godot(monkeypatch, ["x"], code=godot_cmd.TIMED_OUT)
    assert run_verb(["run", "--all"]).checks[0].detail == "timed out"
    # A fresh worktree has no import cache: Godot cannot parse the scenario scripts, and the hint says so.
    fake_godot(monkeypatch, ['SCRIPT ERROR: Parse Error: Identifier "WorkshopScenario" not declared.',
                             "   at: GDScript::reload (res://src/api/workshop/workshop_cli.gd:31)"], code=1)
    detail = run_verb(["run", "--all"]).checks[0].detail
    assert "hx godot check" in detail


@pytest.mark.parametrize("lines, message", [
    (["nothing here"], "no WORKSHOP_JSON_BEGIN..WORKSHOP_JSON_END block"),
    (["WORKSHOP_JSON_BEGIN", "{oops", "WORKSHOP_JSON_END"], "report is not JSON"),
    (["WORKSHOP_JSON_BEGIN", '{"schema": 2, "scenarios": []}', "WORKSHOP_JSON_END"], "report is not schema 1"),
])
def test_parse_report_rejects(lines, message):
    with pytest.raises(ValueError, match=message):
        workshop.parse_report(lines)


def test_usage_errors_exit_2_without_running_godot(monkeypatch, fake_repo):
    write_scenarios(fake_repo)
    calls = fake_godot(monkeypatch, stdout_of(canned()))
    assert run_verb(["run", "rifle_vs_dummy", "--all"]).exit_code == 2
    assert run_verb(["run"]).exit_code == 2
    r = run_verb(["run", "no_such_scenario"])
    assert r.exit_code == 2 and "no scenario 'no_such_scenario'" in r.checks[0].detail
    assert calls == []


def test_missing_godot_binary_fails(monkeypatch, fake_repo):
    write_scenarios(fake_repo)
    monkeypatch.setattr(godot_cmd, "_console", lambda: (None, "no Godot console binary at the repo root"))
    r = run_verb(["run", "--all"])
    assert r.exit_code == 1 and r.checks[0].name == "godot"


def test_list_reads_scenario_files_and_flags_broken_ones(fake_repo, capsys):
    write_scenarios(fake_repo)
    assert main(["workshop", "list", "--json"]) == 1
    d = json.loads(capsys.readouterr().out)
    rows = {row["id"]: row for row in d["tables"]["scenarios"]}
    assert set(rows) == {"rifle_vs_dummy", "rifles_kill_unarmed"}
    assert rows["rifle_vs_dummy"] == {"id": "rifle_vs_dummy", "status": "gate", "component": "fire",
                                      "variants": 2, "probes": 1, "compares": 0}
    assert [c["name"] for c in d["checks"]] == ["scenario file"]
    assert d["checks"][0]["detail"].startswith("broken_file.json:")


def test_workshop_is_a_registered_verb():
    assert "workshop" in VERBS
