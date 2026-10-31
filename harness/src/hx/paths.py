"""Locations. The harness root is this package's project dir; the repo root is
found via git so the harness keeps working if it is lifted into its own repo."""

from __future__ import annotations

import os
import subprocess
from functools import cache
from pathlib import Path

HARNESS_ROOT = Path(__file__).resolve().parents[2]


@cache
def repo_root() -> Path:
    override = os.environ.get("HX_REPO_ROOT")
    if override:
        return Path(override).resolve()
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=HARNESS_ROOT, capture_output=True, text=True, timeout=10, check=True,
        )
        return Path(out.stdout.strip()).resolve()
    except (OSError, subprocess.SubprocessError):
        return HARNESS_ROOT.parent


def data_dir() -> Path:
    override = os.environ.get("HX_DATA_DIR")
    return Path(override) if override else HARNESS_ROOT / "data"
