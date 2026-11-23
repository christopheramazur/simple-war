"""hx status: one-glance orientation for an agent starting work."""

from __future__ import annotations

import json

from hx import godot
from hx.output import FAIL, OK, WARN, Check, Result
from hx.paths import data_dir, repo_root
from hx.proc import run as sh

HELP = "Repo, Godot project and task-tracker state in one compact view"


def add_args(p) -> None:
    p.add_argument("--no-tasks", action="store_true", help="skip the task tracker query (faster)")
    p.add_argument("--short", action="store_true", help="git only: changed files plus the log, no Godot or tasks")
    p.add_argument("--log", type=int, default=None, metavar="N", help="show the last N commits (default 1; 3 with --short)")


def run(args) -> Result:
    root = repo_root()
    r = Result("status")
    n = args.log if args.log is not None else (3 if args.short else 1)
    _git(root, r, n, args.short)
    if args.short:
        return r
    _godot(root, r)
    if not args.no_tasks:
        _tasks(root, r)
    r.data["ledger"] = "present" if (data_dir() / "ledger.duckdb").exists() else "not yet created"
    return r


def _git(root, r: Result, n: int = 1, short: bool = False) -> None:
    head = sh(["git", "status", "--porcelain=v1", "--branch"], cwd=root)
    if not head.ok:
        r.checks.append(Check("git", FAIL, head.err))
        return
    lines = head.out.splitlines()
    branch_line, files = (lines[0] if lines else ""), lines[1:]
    r.data["branch"] = branch_line.removeprefix("## ")
    modified = sum(not f.startswith("??") for f in files)
    untracked = sum(f.startswith("??") for f in files)
    r.data["dirty"] = f"{modified} modified, {untracked} untracked"
    if short:
        r.data["changed"] = files[:30] + ([f"... +{len(files) - 30} more"] if len(files) > 30 else [])
    if n <= 1:
        last = sh(["git", "log", "-1", "--format=%h %s (%cr)"], cwd=root)
        r.data["last_commit"] = last.out if last.ok else None
    elif n > 1:
        log = sh(["git", "log", f"-{n}", "--format=%h %s (%cr)"], cwd=root)
        r.data["last_commits"] = log.out.splitlines() if log.ok else None


def _godot(root, r: Result) -> None:
    bins = godot.binaries(root)
    ed = bins.get("editor")
    r.data["godot"] = godot.binary_version(ed) if ed else None
    if not ed:
        r.checks.append(Check("godot binary", WARN, "no Godot_v*-stable_win64.exe at repo root"))
    proj = godot.read_project(root)
    if not proj:
        r.checks.append(Check("project.godot", FAIL, "missing"))
        return
    r.data["autoloads"] = proj.get("autoloads", [])
    scene = proj.get("main_scene")
    path = godot.res_to_path(root, scene) if scene else None
    if path is None or not path.exists():
        r.checks.append(Check("main scene", WARN, f"{scene or 'unset'} does not exist"))
    else:
        r.checks.append(Check("main scene", OK, scene))


def _tasks(root, r: Result) -> None:
    ready = sh(["bd", "ready", "--json"], cwd=root, timeout=30)
    if not ready.ok:
        r.checks.append(Check("tasks", WARN, ready.err.splitlines()[0] if ready.err else "bd ready failed"))
        return
    try:
        items = json.loads(ready.out or "[]")
    except json.JSONDecodeError:
        r.checks.append(Check("tasks", WARN, "unparseable bd output"))
        return
    active = sh(["bd", "list", "--status", "in_progress", "--json"], cwd=root, timeout=30)
    try:
        doing = json.loads(active.out or "[]") if active.ok else []
    except json.JSONDecodeError:
        doing = []
    r.data["in_progress"] = [f"{i['id']} {i['title']}" for i in doing]
    r.data["ready"] = f"{len(items)}: " + ", ".join(i["id"] for i in items[:8])
