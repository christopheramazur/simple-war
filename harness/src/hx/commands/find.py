"""hx find: search then show context in one bounded call (replaces grep && sed -n 'a,bp').

  hx find <pattern> [path ...] [-C N] [--max N] [-i] [-F] [--glob G]

Prints `file:line: text` for matches and `file-line- text` for context, capped
at --max matches and --max-lines output lines. Paths default to the cwd.
"""

from __future__ import annotations

import fnmatch
import os
import re
from pathlib import Path

from hx.output import FAIL, Check, Result

HELP = "Search files for a pattern and print matches with N lines of context (bounded)"
SKIP_DIRS = {".git", ".godot", ".dolt", ".beads", "node_modules", "__pycache__", ".venv"}


def add_args(p) -> None:
    p.add_argument("pattern")
    p.add_argument("paths", nargs="*", default=["."])
    p.add_argument("-C", "--context", type=int, default=2, help="context lines around a match (default 2)")
    p.add_argument("--max", type=int, default=20, help="stop after this many matching lines (default 20)")
    p.add_argument("--max-lines", type=int, default=120, help="cap on printed lines (default 120)")
    p.add_argument("-i", "--ignore-case", action="store_true")
    p.add_argument("-F", "--fixed", action="store_true", help="pattern is a literal string")
    p.add_argument("--glob", help="only files whose name matches, e.g. '*.gd'")


def _files(paths, glob):
    for p in paths:
        path = Path(p)
        if path.is_file():
            yield path
            continue
        for root, dirs, names in os.walk(path):
            dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
            for n in sorted(names):
                if not glob or fnmatch.fnmatch(n, glob):
                    yield Path(root) / n


def search(pattern, paths, context=2, max_matches=20, max_lines=120, ignore_case=False, fixed=False, glob=None):
    rx = re.compile(re.escape(pattern) if fixed else pattern, re.I if ignore_case else 0)
    out: list[str] = []
    matches = 0
    truncated = False
    for f in _files(paths, glob):
        try:
            lines = f.read_text(encoding="utf-8").splitlines()
        except (UnicodeDecodeError, OSError):
            continue
        hits = [i for i, ln in enumerate(lines) if rx.search(ln)]
        if not hits:
            continue
        name = f.as_posix()
        shown = -1
        for i in hits:
            if matches >= max_matches:
                truncated = True
                break
            matches += 1
            lo, hi = max(0, i - context), min(len(lines) - 1, i + context)
            if lo > shown + 1 and shown >= 0:
                out.append("--")
            for j in range(max(lo, shown + 1), hi + 1):
                sep = ":" if rx.search(lines[j]) else "-"
                out.append(f"{name}{sep}{j + 1}{sep} {lines[j][:300]}")
            shown = hi
        if truncated:
            break
        out.append("--")
    while out and out[-1] == "--":
        out.pop()
    if len(out) > max_lines:
        out = out[:max_lines]
        truncated = True
    if truncated:
        out.append(f"... truncated (--max {max_matches}, --max-lines {max_lines})")
    return out, matches


def run(args) -> Result:
    r = Result("find")
    try:
        out, n = search(args.pattern, args.paths, args.context, args.max, args.max_lines,
                        args.ignore_case, args.fixed, args.glob)
    except re.error as e:
        r.checks.append(Check("pattern", FAIL, f"bad regex: {e}"))
        return r
    r.data["matches"] = n
    r.raw = "\n".join(out) if out else "no matches"
    r.data["lines"] = out
    return r
