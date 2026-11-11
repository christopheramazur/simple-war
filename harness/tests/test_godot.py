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


def test_mock_default_out():
    assert godot_cmd.mock_out("res://src/presentation/mocks/inspection_window_mock.gd", None) ==         "Game Design Document/Mocks/inspection_window.png"
    assert godot_cmd.mock_out("res://x/y.gd", "a.png") == "a.png"
