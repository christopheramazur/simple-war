"""hx scan: list a directory and find files by name in one bounded call (replaces ls && find).

  hx scan <path> [--depth N] [--name GLOB]... [--max N]

Prints the directory's entries (dirs end in /), then, when --name is given,
files/dirs under it (up to --depth levels) whose name matches any glob,
case-insensitively.
"""

from __future__ import annotations

import fnmatch
import os
from pathlib import Path

from hx.output import FAIL, Check, Result

HELP = "List a directory and find entries by case-insensitive name glob (bounded ls + find)"
SKIP_DIRS = {".git", ".godot", ".dolt", ".beads", "node_modules", "__pycache__", ".venv"}


def add_args(p) -> None:
    p.add_argument("path", nargs="?", default=".")
    p.add_argument("--depth", type=int, default=2, help="max depth for --name matches (default 2)")
    p.add_argument("--name", action="append", default=[], metavar="GLOB", help="case-insensitive name glob (repeatable)")
    p.add_argument("--max", type=int, default=50, help="cap on lines per section (default 50)")


def scan(path, depth=2, names=(), max_lines=50):
    root = Path(path)
    entries = sorted(os.listdir(root), key=str.lower)
    listing = [e + "/" if (root / e).is_dir() else e for e in entries]
    found: list[str] = []
    pats = [n.lower() for n in names]
    if pats:
        base = len(root.parts)
        for cur, dirs, files in os.walk(root):
            level = len(Path(cur).parts) - base + 1
            dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS) if level < depth else []
            for n in sorted(dirs + files):
                if any(fnmatch.fnmatch(n.lower(), p) for p in pats):
                    found.append((Path(cur) / n).as_posix())
    return listing, found


def _cap(lines, n):
    return lines[:n] + ([f"... {len(lines) - n} more"] if len(lines) > n else [])


def run(args) -> Result:
    r = Result("scan")
    if not Path(args.path).is_dir():
        r.checks.append(Check("path", FAIL, f"not a directory: {args.path}"))
        return r
    listing, found = scan(args.path, args.depth, args.name, args.max)
    out = [f"{args.path}: {len(listing)} entries", *_cap(listing, args.max)]
    if args.name:
        out += [f"matches ({len(found)}):", *_cap(found, args.max)]
    r.data.update(entries=listing, matches=found)
    r.raw = "\n".join(out)
    return r
