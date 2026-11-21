"""Locations. The harness root is this package's project dir; the repo root is
found via git from the working directory, so hx verbs target the checkout (or
worktree) you are in. State and telemetry stay pinned to the main checkout via
main_root()/data_dir() so worktrees do not fragment them."""

from __future__ import annotations

import os
import subprocess
from functools import cache
from pathlib import Path

HARNESS_ROOT = Path(__file__).resolve().parents[2]


def _git(args: list[str], cwd: Path) -> Path | None:
    try:
        out = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, timeout=10, check=True)
        return Path(out.stdout.strip()).resolve()
    except (OSError, subprocess.SubprocessError):
        return None


@cache
def _toplevel(cwd: Path) -> Path | None:
    return _git(["rev-parse", "--show-toplevel"], cwd)


def repo_root() -> Path:
    """HX_REPO_ROOT wins; else the git repo/worktree containing the CWD; else the package's repo."""
    override = os.environ.get("HX_REPO_ROOT")
    if override:
        return Path(override).resolve()
    return _toplevel(Path.cwd()) or _toplevel(HARNESS_ROOT) or HARNESS_ROOT.parent


repo_root.cache_clear = _toplevel.cache_clear  # test hook (conftest fake_repo)


@cache
def _common_root(cwd: Path) -> Path | None:
    common = _git(["rev-parse", "--path-format=absolute", "--git-common-dir"], cwd)
    return common.parent if common else None


def main_root(start: Path | None = None) -> Path:
    """The main checkout (the parent of the shared .git dir), also when called from a git worktree.
    CWD-first like repo_root(), falling back to the package location outside a repo."""
    cwd = start or Path.cwd()
    return _common_root(cwd) or _common_root(HARNESS_ROOT) or repo_root()


main_root.cache_clear = _common_root.cache_clear


def data_dir() -> Path:
    """Harness state/telemetry, pinned to the main checkout even when the package
    is imported from a worktree. HX_DATA_DIR wins."""
    override = os.environ.get("HX_DATA_DIR")
    if override:
        return Path(override)
    main = main_root()
    for base in (repo_root(), main):
        try:
            return main / HARNESS_ROOT.relative_to(base) / "data"
        except ValueError:
            continue
    return HARNESS_ROOT / "data"
