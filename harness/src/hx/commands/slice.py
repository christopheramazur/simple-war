"""hx slice: print a numbered line range plus whole other files in one call (replaces sed -n 'a,bp' && cat).

  hx slice <path>:<start>-<end> [--also <path>[:<start>-<end>] ...] [--max-lines N]

`path:N` prints from line N to the end, `path:-N` the first N lines, a bare path the whole file.
Output is `== path (a-b of total) ==` then `lineno: text`, capped at --max-lines overall.
"""

from __future__ import annotations

import re
from pathlib import Path

from hx.output import FAIL, Check, Result

HELP = "Print a numbered line range of one file plus other files in one bounded call"
_SPEC = re.compile(r"^(?P<path>.+?)(?::(?P<a>\d*)(?:-(?P<b>\d*))?)?$")


def add_args(p) -> None:
    p.add_argument("spec", help="path[:start-end]")
    p.add_argument("--also", action="append", default=[], metavar="SPEC", help="more path[:start-end] (repeatable)")
    p.add_argument("--max-lines", type=int, default=400, help="cap on printed lines (default 400)")


def parse_spec(spec: str) -> tuple[str, int | None, int | None]:
    if Path(spec).is_file():  # a real path (e.g. with a drive colon) wins over range parsing
        return spec, None, None
    m = _SPEC.match(spec)
    path = m.group("path")
    a, b = m.group("a"), m.group("b")
    if a is None and b is None and ":" not in spec[len(path):]:
        return path, None, None
    start = int(a) if a else None
    if b is None:  # "path:N" -> from N to end; "path:N" with no dash
        return path, start, None
    return path, start, int(b) if b else None


def slice_file(spec: str) -> list[str]:
    path, a, b = parse_spec(spec)
    lines = Path(path).read_text(encoding="utf-8").splitlines()
    total = len(lines)
    lo = max(1, a or 1)
    hi = min(total, b if b is not None else total)
    out = [f"== {Path(path).as_posix()} ({lo}-{hi} of {total}) =="]
    out += [f"{i}: {lines[i - 1]}" for i in range(lo, hi + 1)]
    return out


def render(specs: list[str], max_lines: int = 400) -> list[str]:
    out: list[str] = []
    for s in specs:
        out += slice_file(s)
    if len(out) > max_lines:
        out = out[:max_lines] + [f"... truncated (--max-lines {max_lines})"]
    return out


def run(args) -> Result:
    r = Result("slice")
    try:
        out = render([args.spec, *args.also], args.max_lines)
    except (OSError, UnicodeDecodeError) as e:
        r.checks.append(Check("read", FAIL, str(e)))
        return r
    r.raw = "\n".join(out)
    r.data["lines"] = len(out)
    return r
