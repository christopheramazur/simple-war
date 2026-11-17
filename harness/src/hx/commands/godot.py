"""hx godot: engine checks with error-only output (DESIGN.md §5 seed verbs).

  hx godot check [--no-import] [FILE...]  headless import, then a GDScript parse of every script under
                                 src/ (or only FILEs, which skips the import)
  hx godot test [--dir D] [--file F] [--select S] [--test T]  run GUT headless (all, or a subset) and
                                 print the summary plus failures
  hx godot run <scene|script> [--quit-after N] [--editor]  run one scene or SceneTree script headless;
                                 errors plus the tail of its output (probes, editor plugin load)
  hx godot mock <res://...mock.gd> [--out path.png]  render a UI mock to PNG (opens a window briefly)

Paths may be res://..., or relative to the repo root (src/x.gd, tests/sim).
"""

from __future__ import annotations

import argparse
import re
import subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from hx.output import FAIL, OK, WARN, Check, Result

HELP = ("Godot: check [files] (import + script parse, errors only) | test (GUT, or a subset) | "
        "run (one scene/script headless) | mock (UI mock -> PNG)")
MOCK_RUNNER = "res://src/presentation/mocks/mock_runner.gd"
MOCK_DIR = "Game Design Document/Mocks"
ANSI = re.compile(r"\x1b\[[0-9;]*m")
ERROR = re.compile(r"^(SCRIPT ERROR|ERROR|Parse Error|USER ERROR)\b|: Parse Error:")
MAX_SHOWN = 25
TAIL = 40
TIMED_OUT = -9
# Engine start-up chatter that `run` leaves out of the output tail.
NOISE = re.compile(r"^(Godot Engine v|Vulkan|OpenGL|D3D12|WARNING: Blend file import|\s*$)")


def add_args(p) -> None:
    sub = p.add_subparsers(dest="action", required=True, metavar="<action>")
    sp = sub.add_parser("mock")
    sp.add_argument("mock", help="mock script (res://...) with a static build() -> Control")
    sp.add_argument("--out", help=f"PNG path relative to the repo (default {MOCK_DIR}/<name>.png)")
    sp.add_argument("--json", action="store_true", default=argparse.SUPPRESS)
    sp.add_argument("-v", "--verbose", action="store_true", default=argparse.SUPPRESS)
    sp.add_argument("--timeout", type=float, default=180)
    for name in ("check", "test", "run"):
        sp = sub.add_parser(name)
        sp.add_argument("--json", action="store_true", default=argparse.SUPPRESS)
        sp.add_argument("-v", "--verbose", action="store_true", default=argparse.SUPPRESS)
        sp.add_argument("--timeout", type=float, default=180 if name == "run" else 900)
        if name == "check":
            sp.add_argument("files", nargs="*", help="only parse these scripts (skips the import pass)")
            sp.add_argument("--no-import", action="store_true", help="skip the (slow) resource import pass")
        if name == "test":
            sp.add_argument("--dir", action="append", help="test dir; default res://test and res://tests")
            sp.add_argument("--file", action="append", help="one test script (GUT -gtest); repeatable")
            sp.add_argument("--select", help="only scripts whose name contains this (GUT -gselect)")
            sp.add_argument("--test", dest="unit", help="only tests whose name contains this (GUT -gunit_test_name)")
        if name == "run":
            sp.add_argument("target", nargs="?",
                            help="a scene (.tscn/.scn) or a SceneTree/MainLoop script (.gd); omit with --editor")
            sp.add_argument("--quit-after", type=int,
                            help="quit after N frames (for a scene that never quits; --editor defaults to 200)")
            sp.add_argument("--editor", action="store_true",
                            help="start the editor headless instead, so editor plugins load and report errors")
            sp.add_argument("--tail", type=int, default=TAIL, help=f"output lines to show (default {TAIL})")
            sp.add_argument("extra", nargs="*", help="after --: arguments for the script")


def run(args) -> Result:
    return {"check": _check, "test": _test, "run": _run_one, "mock": _mock}[args.action](args)


def res_path(root: Path, p: str) -> str:
    """res://… as given; a repo-relative or absolute path under the repo becomes res://…."""
    if p.startswith("res://"):
        return p.rstrip("/") if p != "res://" else p
    path = Path(p)
    path = path if path.is_absolute() else root / path
    rel = path.resolve().relative_to(root.resolve()).as_posix()
    return "res://" + ("" if rel == "." else rel)


def _console() -> tuple[Path, Path] | tuple[None, str]:
    from hx import godot, paths
    root = paths.repo_root()
    exe = godot.binaries(root).get("console")
    return (root, exe) if exe else (None, "no Godot console binary at the repo root")


def _run(exe: Path, root: Path, args: list[str], timeout: float, headless: bool = True) -> tuple[int, list[str]]:
    head = ["--headless"] if headless else []
    try:
        p = subprocess.run([str(exe), *head, "--path", str(root), *args], capture_output=True, text=True,
                           encoding="utf-8", errors="replace", timeout=timeout)
        code, out = p.returncode, p.stdout + "\n" + p.stderr
    except subprocess.TimeoutExpired as e:  # keep what it printed: that is usually why it hung
        dec = lambda b: b.decode("utf-8", "replace") if isinstance(b, bytes) else (b or "")
        code, out = TIMED_OUT, dec(e.stdout) + "\n" + dec(e.stderr) + f"\n(timed out after {timeout:g}s)"
    return code, [ANSI.sub("", x).rstrip() for x in out.splitlines()]


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
    if args.files:
        try:
            scripts = [res_path(root, f) for f in args.files]
        except ValueError as e:
            r.checks.append(Check("files", FAIL, f"not under the repo: {e}"))
            return r
        missing = [s for s in scripts if not (root / s[6:]).is_file()]
        if missing:
            r.checks.append(Check("files", FAIL, "no such script: " + ", ".join(missing)))
            return r
    else:
        if not args.no_import:
            _, lines = _run(exe, root, ["--import"], args.timeout)
            imp = errors(lines)
            r.data["import_errors"] = len(imp)
            found += [f"import: {e}" for e in imp]
        src = root / "src"
        scripts = ["res://" + p.relative_to(root).as_posix() for p in sorted(src.rglob("*.gd"))] if src.exists() else []

    def parse(res: str) -> list[str]:
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
    try:
        files = [res_path(root, f) for f in (args.file or [])]
        dirs = [res_path(root, d) for d in (args.dir or [])]
    except ValueError as e:
        r.checks.append(Check("paths", FAIL, f"not under the repo: {e}"))
        return r
    if not files and not dirs:
        dirs = [d for d in ("res://test", "res://tests") if (root / d[6:]).is_dir()]
    if not files and not dirs:
        r.checks.append(Check("tests", WARN, "no res://test or res://tests directory yet"))
        return r
    code, lines = _run(exe, root, gut_args(dirs, files, args.select, args.unit), args.timeout)
    r.data["dirs"] = ", ".join(dirs + files)
    if args.select or args.unit:
        r.data["filter"] = " ".join(x for x in (args.select and f"select={args.select}",
                                                 args.unit and f"test={args.unit}") if x)
    r.data["summary"] = "; ".join(x.strip() for x in lines if SUMMARY.match(x)) or "(no GUT summary found)"
    fails = [x.strip() for x in lines if FAILED.search(x)] + errors(lines)
    if fails:
        r.data["failures"] = "\n  " + "\n  ".join(dict.fromkeys(fails[:MAX_SHOWN]))
    ran = re.search(r"Tests\s+(\d+)", r.data["summary"])
    if code == 0 and not fails and (not ran or int(ran.group(1)) == 0):
        r.checks.append(Check("gut", WARN, "no tests matched"))
        return r
    r.checks.append(Check("gut", OK if code == 0 and not fails else FAIL,
                          "timed out" if code == TIMED_OUT else f"exit {code}"))
    return r


def gut_args(dirs: list[str], files: list[str], select: str | None, unit: str | None) -> list[str]:
    args = ["-s", "addons/gut/gut_cmdln.gd", *[f"-gdir={d}" for d in dirs], *[f"-gtest={f}" for f in files]]
    if select:
        args.append(f"-gselect={select}")
    if unit:
        args.append(f"-gunit_test_name={unit}")
    return args + ["-gexit", "-ginclude_subdirs"]


def run_args(target: str | None, editor: bool, quit_after: int | None, extra: list[str]) -> list[str]:
    """Godot arguments for `hx godot run`: a .gd runs as the main loop (-s), a scene as the main scene."""
    if editor:
        return ["--editor", "--quit-after", str(quit_after or 200)]
    args = ["-s", target] if target.endswith(".gd") else [target]
    if quit_after:
        args += ["--quit-after", str(quit_after)]
    extra = extra[1:] if extra[:1] == ["--"] else extra
    return args + (["--", *extra] if extra else [])


def _run_one(args) -> Result:
    r = Result("godot run")
    root, exe = _console()
    if root is None:
        r.checks.append(Check("godot", FAIL, exe))
        return r
    target = None
    if not args.editor:
        if not args.target:
            r.checks.append(Check("target", FAIL, "give a scene or script, or --editor"))
            return r
        try:
            target = res_path(root, args.target)
        except ValueError as e:
            r.checks.append(Check("target", FAIL, f"not under the repo: {e}"))
            return r
        if not (root / target[6:]).is_file():
            r.checks.append(Check("target", FAIL, f"no such file: {target}"))
            return r
        r.data["target"] = target
    code, lines = _run(exe, root, run_args(target, args.editor, args.quit_after, args.extra or []), args.timeout)
    errs = errors(lines)
    shown = [x for x in lines if not NOISE.match(x)][-args.tail:] if args.tail > 0 else []
    r.data["exit"] = code
    if shown:
        r.data["output"] = "\n  " + "\n  ".join(shown)
    if errs:
        r.data["errors"] = "\n  " + "\n  ".join(errs[:MAX_SHOWN])
    status = OK if code == 0 and not errs else FAIL
    r.checks.append(Check("run", status, "timed out (try --quit-after)" if code == TIMED_OUT else
                          f"exit {code}, {len(errs)} error(s)" if status == FAIL else ""))
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
