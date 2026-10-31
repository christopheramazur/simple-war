import subprocess

import pytest

from hx import paths

PROJECT = """config_version=5

[application]

config/name="t"
run/main_scene="res://src/main.tscn"
config/features=PackedStringArray("4.7", "Forward Plus")

[autoload]

Bus="*res://bus.gd"
Ecs="*uid://abc"
"""


@pytest.fixture
def fake_repo(tmp_path, monkeypatch):
    """A tiny git repo shaped like the game repo, with HX_REPO_ROOT pointing at it."""
    (tmp_path / "project.godot").write_text(PROJECT)
    (tmp_path / "Godot_v4.7.2-stable_win64.exe").write_bytes(b"")
    (tmp_path / "Godot_v4.7.2-stable_win64_console.exe").write_bytes(b"")
    subprocess.run(["git", "init", "-q", "-b", "main"], cwd=tmp_path, check=True)
    monkeypatch.setenv("HX_REPO_ROOT", str(tmp_path))
    paths.repo_root.cache_clear()
    yield tmp_path
    paths.repo_root.cache_clear()
