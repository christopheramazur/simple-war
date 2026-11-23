"""hx wt-status: a worktree's top-level entries plus its short git status in one call
(replaces `ls <dir> | head; git -C <dir> status --short | head`).

  hx wt-status [path] [--limit N]
"""

from __future__ import annotations

import subprocess
from pathlib import Path

from hx.output import FAIL, Check, Result

HELP = "List a worktree's top-level entries and its short git status in one call"


def add_args(p) -> None:
    p.add_argument("path", nargs="?", default=".", help="worktree directory (default .)")
    p.add_argument("--limit", type=int, default=25, help="max lines per section (default 25)")


def _cap(lines: list[str], limit: int) -> list[str]:
    if len(lines) <= limit:
        return lines
    return lines[:limit] + [f"... {len(lines) - limit} more"]


def render(path: Path, limit: int = 25) -> list[str]:
    entries = sorted(e.name + ("/" if e.is_dir() else "") for e in path.iterdir())
    proc = subprocess.run(["git", "-C", str(path), "status", "--short"], capture_output=True, text=True, encoding="utf-8", errors="replace")
    out = [f"== {path.as_posix()} ({len(entries)} entries) =="] + _cap(entries, limit)
    if proc.returncode != 0:
        out += ["== git status ==", f"not a git worktree: {proc.stderr.strip()}"]
        return out
    status = proc.stdout.splitlines()
    out.append(f"== git status ({len(status)} changed) ==" if status else "== git status (clean) ==")
    return out + _cap(status, limit)


def run(args) -> Result:
    r = Result("wt-status")
    path = Path(args.path)
    if not path.is_dir():
        r.checks.append(Check("path", FAIL, f"not a directory: {path}"))
        return r
    r.raw = "\n".join(render(path, args.limit))
    return r
