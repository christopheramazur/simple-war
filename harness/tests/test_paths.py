"""repo_root() is CWD-first (worktree-aware); main_root()/data_dir() stay pinned to the main checkout."""

import subprocess

import pytest

from hx import paths


def _git(cwd, *args):
    subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True)


@pytest.fixture
def repo_with_worktree(tmp_path, monkeypatch):
    """A temp main checkout with one commit, plus a linked worktree on its own branch."""
    main = tmp_path / "main"
    main.mkdir()
    _git(main, "init", "-q", "-b", "main")
    (main / "file.txt").write_text("main", encoding="utf-8")
    _git(main, "add", ".")
    _git(main, "-c", "user.name=t", "-c", "user.email=t@localhost", "commit", "-qm", "init")
    wt = tmp_path / "wt"
    _git(main, "worktree", "add", "-q", "-b", "worker", str(wt))
    monkeypatch.delenv("HX_REPO_ROOT", raising=False)
    monkeypatch.delenv("HX_DATA_DIR", raising=False)
    paths.repo_root.cache_clear()
    paths.main_root.cache_clear()
    yield main, wt
    paths.repo_root.cache_clear()
    paths.main_root.cache_clear()


def test_repo_root_from_worktree_cwd_is_worktree(repo_with_worktree, monkeypatch):
    main, wt = repo_with_worktree
    monkeypatch.chdir(wt)
    assert paths.repo_root() == wt.resolve()
    monkeypatch.chdir(main)
    assert paths.repo_root() == main.resolve()


def test_repo_root_from_worktree_subdir(repo_with_worktree, monkeypatch):
    _, wt = repo_with_worktree
    sub = wt / "src"
    sub.mkdir()
    monkeypatch.chdir(sub)
    assert paths.repo_root() == wt.resolve()


def test_repo_root_override_wins(repo_with_worktree, monkeypatch):
    main, wt = repo_with_worktree
    monkeypatch.chdir(wt)
    monkeypatch.setenv("HX_REPO_ROOT", str(main))
    assert paths.repo_root() == main.resolve()


def test_repo_root_outside_repo_falls_back_to_package(repo_with_worktree, monkeypatch, tmp_path):
    main, _ = repo_with_worktree
    outside = tmp_path / "outside"
    outside.mkdir()
    monkeypatch.chdir(outside)
    monkeypatch.setattr(paths, "HARNESS_ROOT", main / "harness")
    assert paths.repo_root() == main.resolve()


def test_main_root_stays_on_main_from_worktree(repo_with_worktree, monkeypatch):
    main, wt = repo_with_worktree
    monkeypatch.chdir(wt)
    assert paths.main_root() == main.resolve()
    assert paths.main_root(wt) == main.resolve()
    monkeypatch.chdir(main)
    assert paths.main_root() == main.resolve()


def test_data_dir_stays_on_main_even_when_package_is_in_worktree(repo_with_worktree, monkeypatch):
    main, wt = repo_with_worktree
    monkeypatch.chdir(wt)
    monkeypatch.setattr(paths, "HARNESS_ROOT", main / "harness")
    assert paths.data_dir() == main / "harness" / "data"
    monkeypatch.setattr(paths, "HARNESS_ROOT", wt / "harness")
    assert paths.data_dir() == main / "harness" / "data"


def test_data_dir_override_wins(repo_with_worktree, monkeypatch, tmp_path):
    monkeypatch.setenv("HX_DATA_DIR", str(tmp_path / "elsewhere"))
    assert paths.data_dir() == tmp_path / "elsewhere"


def test_bd_runs_in_main_checkout(repo_with_worktree, monkeypatch):
    from hx.commands import task
    main, wt = repo_with_worktree
    monkeypatch.chdir(wt)
    expected = paths.main_root()  # resolve before patching: task.subprocess is the shared module
    seen = {}

    def fake_run(cmd, **kw):
        seen["cwd"] = kw.get("cwd")
        return subprocess.CompletedProcess(cmd, 0, "[]", "")

    monkeypatch.setattr(task.subprocess, "run", fake_run)
    code, _ = task.bd("ready", "--json")
    assert code == 0
    assert seen["cwd"] == expected == main.resolve()
