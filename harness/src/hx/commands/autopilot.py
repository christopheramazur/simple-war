"""hx autopilot: headless Claude Code works `bd ready` beads one at a time, inside the plan's limits.

  hx autopilot start | stop | status       start = the loop as a detached background process
  hx autopilot run [--once] [--bead ID]    the loop in the foreground (--once: one bead, then exit)
  hx autopilot probe                       read the 5-hour and weekly windows now (one haiku call)
Config: harness/config/autopilot.toml. State and logs: harness/data/autopilot/.
"""

from __future__ import annotations

import argparse

from hx.output import FAIL, OK, WARN, Check, Result

HELP = "headless Claude on the bd ready backlog within plan limits: start | stop | status | run | probe"
ACTIONS = ("start", "stop", "status", "run", "probe")


def add_args(p) -> None:
    sub = p.add_subparsers(dest="action", required=True, metavar="<action>")
    for name in ACTIONS:
        sp = sub.add_parser(name)
        sp.add_argument("--json", action="store_true", default=argparse.SUPPRESS)
        sp.add_argument("-v", "--verbose", action="store_true", default=argparse.SUPPRESS)
        if name == "run":
            sp.add_argument("--once", action="store_true", help="work one bead (or none), then exit")
            sp.add_argument("--bead", help="work this bead once, skipping the picker")
        if name == "stop":
            sp.add_argument("--wait", type=float, default=120, help="seconds to wait for the loop to exit")
            sp.add_argument("--after-bead", action="store_true",
                            help="let the running bead finish, start no other, and return at once")


def run(args) -> Result:
    from hx import autopilot as ap
    r = Result(f"autopilot {args.action}")
    a = args.action
    if a == "start":
        r.data["pid"] = ap.start()
        r.data["log"] = str(ap.STATE / "autopilot.log")
    elif a == "stop":
        res = ap.stop(args.wait, after_bead=args.after_bead)
        r.data.update(res)
        if not res["exited"] and not res.get("draining"):
            r.checks.append(Check("stop", FAIL, f"still running after {args.wait:.0f} s; run hx autopilot stop again"))
    elif a == "run":
        done = ap.run_loop(once=args.once or bool(args.bead), bead=args.bead)
        r.data["beads"] = [{k: j.get(k) for k in ("bead", "outcome", "minutes", "turns", "commits", "detail")} for j in done]
    elif a == "probe":
        snaps = ap.probe()
        r.data["readings"] = {s.window: s.used_pct for s in snaps}
        if not snaps:
            r.checks.append(Check("probe", FAIL, "no rate-limit reading came back; see harness/data/autopilot/autopilot.log"))
    s = ap.status()
    if getattr(args, "json", False):
        r.data.update(status=s)
    else:
        r.data["recent"] = "; ".join(f"{j['bead']} {j['outcome']}" for j in s["recent"][:5]) or "none"
    r.checks.append(Check("loop", OK if s["pid"] else WARN, f"running (pid {s['pid']})" if s["pid"] else "not running"))
    r.checks.append(Check("limits", OK if s["gate"] == "go" else WARN, f"{s['gate']}: {s['why']}"))
    if s["current"]:
        r.data["working"] = f"{s['current']} since {s['since']}"
    return r
