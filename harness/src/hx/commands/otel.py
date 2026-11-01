"""hx otel: OTLP receiver for Claude Code telemetry (DESIGN.md §2).

  hx otel start | stop | status     background receiver on 127.0.0.1:4318 (SessionStart starts it)
  hx otel serve                     the receiver itself (foreground)
"""

from __future__ import annotations

import argparse

from hx.output import FAIL, OK, Check, Result

HELP = "OTLP receiver for Claude Code telemetry: start | stop | status | serve"


def add_args(p) -> None:
    sub = p.add_subparsers(dest="action", required=True, metavar="<action>")
    for name in ("start", "stop", "status", "serve"):
        sp = sub.add_parser(name)
        sp.add_argument("--json", action="store_true", default=argparse.SUPPRESS)
        sp.add_argument("-v", "--verbose", action="store_true", default=argparse.SUPPRESS)


def run(args) -> Result:
    from hx import otel
    r = Result(f"otel {args.action}")
    if args.action == "serve":
        otel.serve()
    elif args.action == "start":
        ok, msg = otel.start()
        r.checks.append(Check("receiver", OK if ok else FAIL, msg))
    elif args.action == "stop":
        r.data["stopped"] = otel.stop()
    else:
        r.data["url"] = f"http://{otel.HOST}:{otel.PORT}"
        r.data["running"] = otel.alive()
        files = sorted(otel.raw_dir().glob("*.jsonl"))
        r.data["raw_files"] = len(files)
        r.data["last_payload"] = files[-1].read_text(encoding="utf-8").splitlines()[-1][:40] if files and files[-1].stat().st_size else "none"
    return r
