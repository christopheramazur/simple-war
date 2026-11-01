"""hx task: the only tracker interface agents use (DESIGN.md §10). Today an adapter over bd;
swapping trackers means replacing this file.

  hx task ready                     unblocked work
  hx task show <id>
  hx task claim <id>                start work (telemetry attributes spend to the task from here)
  hx task close <id> [--reason ..]
  hx task new "title" [-d ..] [-p 0-4] [-t task|bug|feature] [-l a,b] [--parent id]
  hx task note <id> "text"          append to the task's notes (hand-offs)
"""

from __future__ import annotations

import argparse
import json
import subprocess

from hx.output import FAIL, Check, Result

HELP = "Task tracker adapter (bd today): ready | show | claim | close | new | note"


def add_args(p) -> None:
    sub = p.add_subparsers(dest="action", required=True, metavar="<action>")
    for name in ("ready", "show", "claim", "close", "new", "note"):
        sp = sub.add_parser(name)
        sp.add_argument("--json", action="store_true", default=argparse.SUPPRESS)
        sp.add_argument("-v", "--verbose", action="store_true", default=argparse.SUPPRESS)
        if name in ("show", "claim", "close", "note"):
            sp.add_argument("id")
        if name == "close":
            sp.add_argument("--reason", default="")
        if name == "note":
            sp.add_argument("text")
        if name == "new":
            sp.add_argument("title")
            sp.add_argument("-d", "--description", default="")
            sp.add_argument("-p", "--priority", default="2")
            sp.add_argument("-t", "--type", default="task")
            sp.add_argument("-l", "--labels", default="")
            sp.add_argument("--parent")


def bd(*args: str) -> tuple[int, str]:
    from hx import paths
    p = subprocess.run(["bd", *args], capture_output=True, text=True, encoding="utf-8", errors="replace",
                       cwd=paths.repo_root())
    return p.returncode, (p.stdout if p.returncode == 0 else (p.stderr or p.stdout)).strip()


def _row(x: dict) -> dict:
    return {"id": x["id"], "p": x.get("priority"), "type": x.get("issue_type"), "status": x.get("status"),
            "title": x["title"][:80]}


def run(args) -> Result:
    r = Result(f"task {args.action}")
    a = args.action
    if a == "ready":
        code, out = bd("ready", "--json")
        if code == 0:
            r.tables["ready"] = [_row(x) for x in json.loads(out or "[]") if x.get("issue_type") != "epic"]
    elif a == "show":
        code, out = bd("show", args.id, "--json")
        if code == 0:
            d = json.loads(out)
            d = d[0] if isinstance(d, list) else d
            r.data.update({k: d.get(k) for k in ("id", "title", "status", "priority", "issue_type", "assignee",
                                                 "description", "notes") if d.get(k)})
            deps = d.get("dependencies") or []
            if deps:
                r.data["depends_on"] = ", ".join(f"{x.get('id')} ({x.get('status')})" for x in deps)
    elif a == "claim":
        code, out = bd("update", args.id, "--claim")
    elif a == "close":
        code, out = bd("close", args.id, *(["--reason", args.reason] if args.reason else []))
    elif a == "note":
        code, out = bd("update", args.id, "--append-notes", args.text)
    else:  # new
        extra = ["-l", args.labels] if args.labels else []
        extra += ["--parent", args.parent] if args.parent else []
        code, out = bd("create", args.title, "-t", args.type, "-p", str(args.priority),
                       "-d", args.description, *extra, "--silent")
        if code == 0:
            r.data["id"] = out
    if code != 0:
        r.checks.append(Check("bd", FAIL, out[-300:]))
    elif a in ("claim", "close", "note"):
        r.data["ok"] = out.splitlines()[-1][:200] if out else "done"
    return r
