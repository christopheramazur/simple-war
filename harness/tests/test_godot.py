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
