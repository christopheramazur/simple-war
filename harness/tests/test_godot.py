from hx import godot
from hx.commands import godot as godot_cmd


def test_binaries_pick_newest(tmp_path):
    for name in ["Godot_v4.6-stable_win64.exe", "Godot_v4.7.2-stable_win64.exe",
                 "Godot_v4.7.2-stable_win64_console.exe", "Godot_v4.10-stable_win64.exe"]:
        (tmp_path / name).write_bytes(b"")
    bins = godot.binaries(tmp_path)
    assert godot.binary_version(bins["editor"]) == "4.10"
    assert godot.binary_version(bins["console"]) == "4.7.2"


def test_read_project(fake_repo):
    info = godot.read_project(fake_repo)
    assert info["main_scene"] == "res://src/main.tscn"
    assert info["features"] == ["4.7", "Forward Plus"]
    assert info["autoloads"] == ["Bus", "Ecs"]


def test_res_to_path(tmp_path):
    assert godot.res_to_path(tmp_path, "res://a/b.tscn") == tmp_path / "a" / "b.tscn"
    assert godot.res_to_path(tmp_path, "uid://x") is None


def _parse(*argv):
    import argparse
    p = argparse.ArgumentParser()
    godot_cmd.add_args(p)
    return p.parse_args(argv)


def test_res_path_accepts_res_and_repo_paths(tmp_path):
    assert godot_cmd.res_path(tmp_path, "res://tests/sim/") == "res://tests/sim"
    assert godot_cmd.res_path(tmp_path, "tests/sim") == "res://tests/sim"
    assert godot_cmd.res_path(tmp_path, str(tmp_path / "src" / "a.gd")) == "res://src/a.gd"
    import pytest
    with pytest.raises(ValueError):
        godot_cmd.res_path(tmp_path / "repo", str(tmp_path / "elsewhere.gd"))


def test_gut_args_for_a_subset():
    assert godot_cmd.gut_args(["res://tests/sim"], ["res://tests/t.gd"], "test_battle", "refuses") == [
        "-s", "addons/gut/gut_cmdln.gd", "-gdir=res://tests/sim", "-gtest=res://tests/t.gd",
        "-gselect=test_battle", "-gunit_test_name=refuses", "-gexit", "-ginclude_subdirs"]


def test_run_args_script_scene_editor():
    assert godot_cmd.run_args("res://p.gd", False, None, ["--", "--a", "1"]) == ["-s", "res://p.gd", "--", "--a", "1"]
    assert godot_cmd.run_args("res://m.tscn", False, 30, []) == ["res://m.tscn", "--quit-after", "30"]
    assert godot_cmd.run_args(None, True, None, []) == ["--editor", "--quit-after", "200"]


def test_run_options_after_the_target_are_not_swallowed():
    a = _parse("run", "src/m.tscn", "--quit-after", "30", "--timeout", "8", "--", "--alpha", "1")
    assert (a.target, a.quit_after, a.timeout, a.extra) == ("src/m.tscn", 30, 8.0, ["--alpha", "1"])
    a = _parse("check", "src/a.gd", "src/b.gd")
    assert a.files == ["src/a.gd", "src/b.gd"]
    a = _parse("test", "--select", "battle", "--test", "refuses")
    assert (a.select, a.unit, a.dir, a.file) == ("battle", "refuses", None, None)


def test_mock_default_out():
    assert godot_cmd.mock_out("res://src/presentation/mocks/inspection_window_mock.gd", None) ==         "Game Design Document/Mocks/inspection_window.png"
    assert godot_cmd.mock_out("res://x/y.gd", "a.png") == "a.png"


def test_mock_variant_paths():
    assert godot_cmd.mock_variant_paths("a/b/x.png") == [
        "a/b/x_greyscale.png", "a/b/x_protan.png", "a/b/x_deutan.png"]


def test_check_reports_native_method_lint(fake_repo, monkeypatch):
    (fake_repo / "src").mkdir()
    (fake_repo / "src" / "a.gd").write_text("extends Node\n")
    calls = []

    def fake_run(exe, root, args, timeout, headless=True):
        calls.append(args)
        if "--check-only" in args:
            return 0, []
        return 0, ["noise", "NMLINT res://src/a.gd:3: c is Control, which has no method to_global()"]
    monkeypatch.setattr(godot_cmd, "_run", fake_run)
    r = godot_cmd._check(_parse("check", "src/a.gd"))
    assert r.data["errors"] == 1
    assert "to_global()" in r.data["shown"]
    assert any(godot_cmd.NATIVE_LINT in a for a in calls)


# GUT's output for a file with one passing, one pending and one failing test (sw-lzg).
GUT_MIXED = [
    "res://tests/t.gd",
    "* test_passes",
    "* test_pending_one",
    "    [Pending]:  not written yet",
    "* test_fails_one",
    "    [Failed]:  [1] expected to equal [2]:  deliberate failure",
    "      at line 10",
    "3 tests",
    "= Run Summary",
    "res://tests/t.gd",
    "- test_pending_one",
    "    [Pending]:  not written yet",
    "- test_fails_one",
    "    [Failed]:  [1] expected to equal [2]:  deliberate failure",
    "          at line 10",
    "Totals",
    "Passing Tests         1",
    "Failing Tests         1",
    "Risky/Pending         1",
    "Asserts             1/2",
]


def _gut_check(monkeypatch, tmp_path, lines, code):
    monkeypatch.setattr(godot_cmd, "_console", lambda: (tmp_path, tmp_path / "godot.exe"))
    monkeypatch.setattr(godot_cmd, "_run", lambda *a, **k: (code, lines))
    r = godot_cmd._test(_parse("test", "--file", "tests/t.gd"))
    return r, r.checks[0]


def test_gut_pending_only_is_not_ok_even_though_gut_exits_0(monkeypatch, tmp_path):
    lines = ["- test_pending_one", "    [Pending]:  not written yet", "Passing Tests      none",
             "Risky/Pending         1", "Tests                 1"]
    r, check = _gut_check(monkeypatch, tmp_path, lines, 0)
    assert check.status == godot_cmd.FAIL
    assert check.detail == "1 pending"
    assert r.data["not_passing"] == "\n  test_pending_one: [Pending]:  not written yet"


def test_gut_failing_and_pending_names_both_tests(monkeypatch, tmp_path):
    r, check = _gut_check(monkeypatch, tmp_path, GUT_MIXED, 1)
    assert check.status == godot_cmd.FAIL
    assert check.detail == "exit 1, 1 failing, 1 pending"
    assert "test_pending_one: [Pending]:  not written yet" in r.data["not_passing"]
    assert "test_fails_one: [Failed]:  [1] expected to equal [2]:  deliberate failure" in r.data["not_passing"]
    assert "Risky/Pending         1" in r.data["summary"]


def test_gut_all_passing_is_ok(monkeypatch, tmp_path):
    lines = ["* test_a", "Passing Tests         2", "Tests                 2", "Asserts             3"]
    r, check = _gut_check(monkeypatch, tmp_path, lines, 0)
    assert check.status == godot_cmd.OK
    assert "not_passing" not in r.data
