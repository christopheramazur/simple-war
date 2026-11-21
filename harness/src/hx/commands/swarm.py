"""hx swarm: the Qwen4 Max swarm (harness/swarm/README.md).

Lifecycle (the user or a Claude session):
  hx swarm start | stop | status | run            run = the supervisor loop in the foreground
Agent verbs (used by the Qwen role agents inside their turns):
  hx swarm spawn <bead> [--note ...]               orchestrator: queue a Qwen worker in its own worktree
  hx swarm workers                                 list worker jobs
  hx swarm merge <bead>                            orchestrator: test the branch on top of main, fast-forward main
  hx swarm reject <bead> --reason ...              orchestrator: drop a worker's branch and worktree
  hx swarm research "<topic>"                      researchers: queue a deep-research turn
  hx swarm mail <to> "<message>"                   to: orchestrator | designers | researchers | auditor | a role name
  hx swarm ask "<question>"                        anyone: ask the designers (stand-ins for the user)
  hx swarm usage [--minutes 30]                    models, calls, tokens and cost in the window
  hx swarm selfcheck                               orchestrator: am I still Qwen-only and running?
  hx swarm verdict PASS|WARN|FAIL "<reason>"       auditor: record the audit verdict
  hx swarm commit -m "<msg>" [paths...]            commit docs/swarm (+ paths) in the main checkout and push
"""

from __future__ import annotations

import argparse
import json
import os

from hx.output import FAIL, OK, WARN, Check, Result

HELP = "Qwen4 Max swarm: start | stop | status | spawn | merge | reject | research | mail | ask | usage | selfcheck | verdict"

ACTIONS = ("start", "stop", "status", "run", "spawn", "workers", "merge", "reject", "research", "mail", "ask", "usage",
           "selfcheck", "verdict", "commit")


def add_args(p) -> None:
    sub = p.add_subparsers(dest="action", required=True, metavar="<action>")
    for name in ACTIONS:
        sp = sub.add_parser(name)
        sp.add_argument("--json", action="store_true", default=argparse.SUPPRESS)
        sp.add_argument("-v", "--verbose", action="store_true", default=argparse.SUPPRESS)
        if name in ("spawn", "merge", "reject"):
            sp.add_argument("bead")
        if name == "spawn":
            sp.add_argument("--note", default="", help="guidance for the worker")
            sp.add_argument("--fresh", action="store_true", help="start over from main instead of continuing the branch")
        if name == "reject":
            sp.add_argument("--reason", required=True)
        if name in ("research", "ask"):
            sp.add_argument("text")
        if name == "mail":
            sp.add_argument("to")
            sp.add_argument("text")
        if name == "usage":
            sp.add_argument("--minutes", type=int, default=30)
        if name == "verdict":
            sp.add_argument("verdict", choices=["PASS", "WARN", "FAIL"])
            sp.add_argument("reason")
        if name == "commit":
            sp.add_argument("-m", "--message", required=True)
            sp.add_argument("paths", nargs="*")


def _me() -> str:
    return os.environ.get("HX_SWARM_ROLE") or "user"


def run(args) -> Result:
    from hx import swarm
    r = Result(f"swarm {args.action}")
    a = args.action
    try:
        if a == "start":
            r.data["pid"] = swarm.start()
            r.data["log"] = str(swarm.STATE / "supervisor.log")
        elif a == "stop":
            r.data["was_running"] = swarm.stop()
            r.data["note"] = "STOP file written; running turns finish, then the supervisor exits"
        elif a == "run":
            swarm.Supervisor().run()
        elif a == "status":
            swarm.write_status()
            r.raw = (swarm.DOCS / "STATUS.md").read_text(encoding="utf-8")
        elif a == "spawn":
            j = swarm.spawn_worker(args.bead, args.note, args.fresh)
            r.data.update(bead=j["bead"], worktree=j["worktree"], branch=j["branch"], attempt=j["attempts"])
        elif a == "workers":
            r.tables["workers"] = [{"bead": j["bead"], "status": j["status"], "attempts": j["attempts"],
                                    "commits": j.get("commits", ""), "created": j["created"][5:16]}
                                   for j in swarm.jobs() if j["status"] not in swarm.DONE or args.verbose]
        elif a == "merge":
            r.data["result"] = swarm.merge_worker(args.bead)
        elif a == "reject":
            r.data["result"] = swarm.reject_worker(args.bead, args.reason)
        elif a == "research":
            r.data["queued"] = swarm.queue_research(args.text, _me())
        elif a == "mail":
            r.data["delivered_to"] = swarm.send_mail(args.to, _me(), args.text)
        elif a == "ask":
            swarm.ask(args.text, _me())
            r.data["asked"] = "designers (answers arrive in your inbox)"
        elif a == "usage":
            r.raw = json.dumps(swarm.usage(args.minutes), indent=1)
        elif a == "selfcheck":
            sc = swarm.selfcheck()
            r.raw = json.dumps(sc, indent=1)
            if not sc["config_ok"] or sc["non_qwen_swarm_calls_30m"]:
                r.exit_override = 1
        elif a == "verdict":
            swarm.event("verdict", verdict=args.verdict, reason=args.reason[:2000], by=_me())
            r.data["recorded"] = args.verdict
        elif a == "commit":
            r.data["result"] = swarm.commit_docs(args.message, args.paths)
    except (ValueError, TimeoutError, RuntimeError) as e:
        r.checks.append(Check(a, FAIL, str(e)))
    return r


__all__ = ["run", "add_args", "HELP", "OK", "WARN"]
