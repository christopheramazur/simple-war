import json

import pytest

from hx.cli import main


def test_status_json(fake_repo, capsys):
    code = main(["status", "--no-tasks", "--json"])
    d = json.loads(capsys.readouterr().out)
    assert code == 0
    assert d["data"]["godot"] == "4.7.2"
    assert d["data"]["autoloads"] == ["Bus", "Ecs"]
    assert d["data"]["branch"].startswith("No commits yet on main") or "main" in d["data"]["branch"]
    main_scene = next(c for c in d["checks"] if c["name"] == "main scene")
    assert main_scene["status"] == "warn"  # res://src/main.tscn does not exist


def test_status_main_scene_ok(fake_repo, capsys):
    (fake_repo / "src").mkdir()
    (fake_repo / "src" / "main.tscn").write_text("")
    main(["status", "--no-tasks"])
    out = capsys.readouterr().out
    assert "main scene" not in out  # passing checks are hidden in compact mode


def test_doctor_flags_secret(fake_repo, capsys):
    (fake_repo / "leak.txt").write_text("sk-" + "ant-" + "z" * 40)
    code = main(["doctor", "--json"])
    d = json.loads(capsys.readouterr().out)
    secrets = next(c for c in d["checks"] if c["name"] == "secrets")
    assert code == 1 and secrets["status"] == "fail" and "leak.txt" in secrets["detail"]


def test_unknown_verb_exits():
    with pytest.raises(SystemExit):
        main(["nope"])
