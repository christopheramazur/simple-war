"""hx godot: engine checks with error-only output (DESIGN.md §5 seed verbs).

  hx godot check [--no-import]   headless import, then a GDScript parse of every script under src/
  hx godot test [--dir res://test]  run GUT headless and print the summary plus failures
  hx godot mock <res://...mock.gd> [--out path.png]  render a UI mock to PNG (opens a window briefly)
"""

from __future__ import annotations

import argparse
import re
import subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from hx.output import FAIL, OK, WARN, Check, Result

HELP = "Godot: check (import + script parse, errors only) | test (GUT summary) | mock (UI mock -> PNG)"
MOCK_RUNNER = "res://src/presentation/mocks/mock_runner.gd"
MOCK_DIR = "Game Design Document/Mocks"
ANSI = re.compile(r"\x1b\[[0-9;]*m")
ERROR = re.compile(r"^(SCRIPT ERROR|ERROR|Parse Error|USER ERROR)\b|: Parse Error:")
MAX_SHOWN = 25


def add_args(p) -> None:
    sub = p.add_subparsers(dest="action", required=True, metavar="<action>")
    sp = sub.add_parser("mock")
    sp.add_argument("mock", help="mock script (res://...) with a static build() -> Control")
    sp.add_argument("--out", help=f"PNG path relative to the repo (default {MOCK_DIR}/<name>.png)")
    sp.add_argument("--json", action="store_true", default=argparse.SUPPRESS)
    sp.add_argument("-v", "--verbose", action="store_true", default=argparse.SUPPRESS)
    sp.add_argument("--timeout", type=float, default=180)
    for name in ("check", "test"):
        sp = sub.add_parser(name)
        sp.add_argument("--json", action="store_true", default=argparse.SUPPRESS)
        sp.add_argument("-v", "--verbose", action="store_true", default=argparse.SUPPRESS)
        sp.add_argument("--timeout", type=float, default=900)
        if name == "check":
            sp.add_argument("--no-import", action="store_true", help="skip the (slow) resource import pass")
        if name == "test":
            sp.add_argument("--dir", action="append", help="test dir (res://...); default res://test and res://tests")


def run(args) -> Result:
    return {"check": _check, "test": _test, "mock": _mock}[args.action](args)


def _console() -> tuple[Path, Path] | tuple[None, str]:
    from hx import godot, paths
    root = paths.repo_root()
    exe = godot.binaries(root).get("console")
    return (root, exe) if exe else (None, "no Godot console binary at the repo root")


def _run(exe: Path, root: Path, args: list[str], timeout: float, headless: bool = True) -> tuple[int, list[str]]:
    head = ["--headless"] if headless else []
    p = subprocess.run([str(exe), *head, "--path", str(root), *args], capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=timeout)
    return p.returncode, [ANSI.sub("", x).rstrip() for x in (p.stdout + "\n" + p.stderr).splitlines()]


def errors(lines: list[str]) -> list[str]:
    """Error lines, each with its following `at:` location line when Godot prints one."""
    out = []
    for i, line in enumerate(lines):
        if ERROR.search(line.strip()):
            nxt = lines[i + 1].strip() if i + 1 < len(lines) else ""
            out.append(line.strip() + (f"  ({nxt[3:].strip()})" if nxt.startswith("at:") else ""))
    return list(dict.fromkeys(out))  # Godot repeats some errors; keep order, drop duplicates


def _check(args) -> Result:
    r = Result("godot check")
    root, exe = _console()
    if root is None:
        r.checks.append(Check("godot", FAIL, exe))
        return r
    found: list[str] = []
    if not args.no_import:
        _, lines = _run(exe, root, ["--import"], args.timeout)
        imp = errors(lines)
        r.data["import_errors"] = len(imp)
        found += [f"import: {e}" for e in imp]
    scripts = sorted(p for p in (root / "src").rglob("*.gd")) if (root / "src").exists() else []

    def parse(f: Path) -> list[str]:
        res = "res://" + f.relative_to(root).as_posix()
        _, lines = _run(exe, root, ["--check-only", "--script", res], 120)
        return [f"{res}: {e}" for e in errors(lines)]
    with ThreadPoolExecutor(max_workers=4) as pool:
        for errs in pool.map(parse, scripts):
            found += errs
    r.data["scripts_parsed"] = len(scripts)
    r.data["errors"] = len(found)
    if found:
        r.data["shown"] = "\n  " + "\n  ".join(found[:MAX_SHOWN]) + (
            f"\n  ... {len(found) - MAX_SHOWN} more" if len(found) > MAX_SHOWN else "")
    r.checks.append(Check("godot check", FAIL if found else OK, f"{len(found)} error(s)" if found else ""))
    return r


SUMMARY = re.compile(r"^\s*(Tests|Passing( Tests)?|Failing( Tests)?|Pending|Asserts|Scripts|Time)\b.*\d", re.I)
FAILED = re.compile(r"\[Failed\]|^\s*FAILED|- test_\w+.*fail", re.I)


def _test(args) -> Result:
    r = Result("godot test")
    root, exe = _console()
    if root is None:
        r.checks.append(Check("godot", FAIL, exe))
        return r
    dirs = args.dir or [d for d in ("res://test", "res://tests") if (root / d[6:]).is_dir()]
    if not dirs:
        r.checks.append(Check("tests", WARN, "no res://test or res://tests directory yet"))
        return r
    code, lines = _run(exe, root, ["-s", "addons/gut/gut_cmdln.gd", *[f"-gdir={d}" for d in dirs],
                                   "-gexit", "-ginclude_subdirs"], args.timeout)
    r.data["dirs"] = ", ".join(dirs)
    r.data["summary"] = "; ".join(x.strip() for x in lines if SUMMARY.match(x)) or "(no GUT summary found)"
    fails = [x.strip() for x in lines if FAILED.search(x)] + errors(lines)
    if fails:
        r.data["failures"] = "\n  " + "\n  ".join(dict.fromkeys(fails[:MAX_SHOWN]))
    r.checks.append(Check("gut", OK if code == 0 and not fails else FAIL, f"exit {code}"))
    return r


def mock_out(mock: str, out: str | None) -> str:
    """Default output: the mock's name without a trailing _mock, under MOCK_DIR."""
    if out:
        return out
    name = mock.rsplit("/", 1)[-1].removesuffix(".gd").removesuffix("_mock")
    return f"{MOCK_DIR}/{name}.png"


def _mock(args) -> Result:
    r = Result("godot mock")
    root, exe = _console()
    if root is None:
        r.checks.append(Check("godot", FAIL, exe))
        return r
    out = mock_out(args.mock, args.out)
    # A real renderer is needed: --headless draws nothing.
    code, lines = _run(exe, root, ["-s", MOCK_RUNNER, "--", "--mock", args.mock, "--out", out],
                       args.timeout, headless=False)
    errs = errors(lines)
    wrote = [x for x in lines if x.startswith("mock_runner: wrote")]
    r.data["out"] = out
    if wrote:
        r.data["image"] = wrote[-1].removeprefix("mock_runner: wrote ").strip()
    if errs:
        r.data["errors"] = "\n  " + "\n  ".join(errs[:MAX_SHOWN])
    r.checks.append(Check("mock", OK if code == 0 and wrote and not errs else FAIL, f"exit {code}"))
    return r
