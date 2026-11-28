"""clear_generated_uids: untracked Godot .uid files in main must not block a branch's fast-forward."""
import subprocess

from hx import swarm


def _g(root, *a):
    return subprocess.run(["git", *a], cwd=root, capture_output=True, text=True, check=True).stdout


def test_untracked_uid_the_branch_adds_is_cleared_and_ff_succeeds(tmp_path):
    r = tmp_path
    _g(r, "init", "-q", "-b", "main")
    _g(r, "config", "user.email", "t@t"); _g(r, "config", "user.name", "t")
    (r / "a.gd").write_text("x\n"); _g(r, "add", "."); _g(r, "commit", "-qm", "a")
    _g(r, "checkout", "-qb", "feat")
    (r / "a.gd.uid").write_text("uid://branch\n"); _g(r, "add", "."); _g(r, "commit", "-qm", "uid")
    _g(r, "checkout", "-q", "main")
    (r / "a.gd.uid").write_text("uid://imported\n")  # what an import in the main checkout writes
    (r / "keep.gd.uid").write_text("uid://other\n")  # untracked, but the branch doesn't add it
    (r / "notes.txt").write_text("mine\n")
    assert subprocess.run(["git", "merge", "--ff-only", "feat"], cwd=r, capture_output=True).returncode  # blocked
    assert swarm.clear_generated_uids("feat", root=r) == ["a.gd.uid"]
    _g(r, "merge", "--ff-only", "feat")
    assert (r / "a.gd.uid").read_text() == "uid://branch\n"
    assert (r / "keep.gd.uid").exists() and (r / "notes.txt").exists()


def test_nothing_to_clear(tmp_path):
    r = tmp_path
    _g(r, "init", "-q", "-b", "main")
    _g(r, "config", "user.email", "t@t"); _g(r, "config", "user.name", "t")
    (r / "a.gd").write_text("x\n"); _g(r, "add", "."); _g(r, "commit", "-qm", "a")
    _g(r, "branch", "feat")
    assert swarm.clear_generated_uids("feat", root=r) == []
