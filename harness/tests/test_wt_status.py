import subprocess

from hx.commands.wt_status import render


def test_render_dirty_and_clean(tmp_path):
    subprocess.run(["git", "init", "-q", str(tmp_path)], check=True)
    (tmp_path / "a.txt").write_text("x")
    (tmp_path / "sub").mkdir()
    out = render(tmp_path)
    assert "a.txt" in out and "sub/" in out
    assert any(l.startswith("== git status (1 changed)") for l in out)
    assert render(tmp_path, limit=1)[-1].startswith("?? ") or "more" in render(tmp_path, limit=1)[2]


def test_not_a_repo(tmp_path):
    out = render(tmp_path)
    assert "not a git worktree" in out[-1] or any("not a git" in l for l in out)
