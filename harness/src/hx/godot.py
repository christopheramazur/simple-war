"""Read-only facts about the Godot project (no engine launch)."""

from __future__ import annotations

import re
from pathlib import Path

_BIN_RE = re.compile(r"^Godot_v(?P<ver>[\w.\-]+?)-stable_win64(?P<console>_console)?\.exe$")


def binaries(root: Path) -> dict[str, Path]:
    """Map 'editor'/'console' -> binary path for the newest version at repo root."""
    found: dict[str, tuple[str, Path]] = {}
    for p in root.glob("Godot_v*-stable_win64*.exe"):
        m = _BIN_RE.match(p.name)
        if not m:
            continue
        kind = "console" if m["console"] else "editor"
        if kind not in found or _vkey(m["ver"]) > _vkey(found[kind][0]):
            found[kind] = (m["ver"], p)
    return {k: v[1] for k, v in found.items()}


def binary_version(path: Path) -> str | None:
    m = _BIN_RE.match(path.name)
    return m["ver"] if m else None


def _vkey(v: str) -> tuple[int, ...]:
    return tuple(int(x) for x in re.findall(r"\d+", v))


def read_project(root: Path) -> dict:
    """Parse the bits of project.godot we report on."""
    f = root / "project.godot"
    if not f.exists():
        return {}
    section, info, autoloads = "", {}, []
    for line in f.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
        elif "=" in line and not line.startswith(";"):
            key, val = line.split("=", 1)
            if section == "application" and key == "run/main_scene":
                info["main_scene"] = val.strip('"')
            elif section == "application" and key == "config/features":
                info["features"] = re.findall(r'"([^"]+)"', val)
            elif section == "autoload":
                autoloads.append(key)
    info["autoloads"] = autoloads
    return info


def res_to_path(root: Path, res: str) -> Path | None:
    return root / res[len("res://"):] if res.startswith("res://") else None
