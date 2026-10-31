"""hx delegate: hand a task to the cheapest model the routing table trusts (DESIGN.md §7).

  hx delegate --level L1 --class csv_to_json --input data.csv "Convert to a JSON array ..."
  echo "..." | hx delegate --level L3 --class log_triage
  hx delegate --level L5 --agent "Rename X to Y in src/"   (headless OpenCode, edits the tree)

Prints the model's output to stdout and one status line to stderr.
Exit codes: 0 handed off, 2 escalate (no trusted model available: do it yourself), 1 error.
"""

from __future__ import annotations

import sys
from pathlib import Path

from hx.output import FAIL, WARN, Check, Result

HELP = "Hand a task to the cheapest trusted model (routing table); exit 2 = escalate"


def add_args(p) -> None:
    p.add_argument("prompt", nargs="?", help="the task; read from stdin when omitted")
    p.add_argument("--level", required=True, help="L1..L5 (DESIGN.md §8)")
    p.add_argument("--class", dest="task_class", help="task class, e.g. csv_to_json (see config/routing.toml)")
    p.add_argument("--size", choices=["s", "m", "l"], help="default: guessed from prompt length")
    p.add_argument("--input", action="append", default=[], help="file appended to the prompt (repeatable)")
    p.add_argument("--agent", action="store_true", help="tool-using run via headless OpenCode")
    p.add_argument("--no-start", action="store_true", help="don't start the local model if it is down")
    p.add_argument("--timeout", type=float, default=900)


def run(args) -> Result:
    from hx import delegate
    r = Result("delegate")
    prompt = args.prompt if args.prompt is not None else sys.stdin.read()
    for f in args.input:
        prompt += f"\n\n--- {Path(f).name} ---\n" + Path(f).read_text(encoding="utf-8", errors="replace")
    if not prompt.strip():
        r.checks.append(Check("prompt", FAIL, "empty prompt"))
        return r
    fn = delegate.run_agent if args.agent else delegate.run
    out = fn(prompt, args.level, args.task_class, args.size, start_local=not args.no_start, timeout=args.timeout)
    r.data.update({"route": out.route, "match": out.match, "target": out.target, "model": out.model,
                   "verdict": out.verdict, "needs_review": out.needs_review, "escalate": out.escalate,
                   "latency_s": out.latency_s, "output_tokens": out.output_tokens, "tried": out.tried})
    if out.escalate:
        r.checks.append(Check("escalate", WARN, "no trusted model available; do the task yourself"))
        r.exit_override = 2
    else:
        r.data["output"] = out.text
        if not args.json:  # stdout = the model's output only, status on stderr
            print(f"[delegate] {out.model} via {out.route} ({out.match}, {out.verdict}"
                  f"{', REVIEW IT' if out.needs_review else ''}) {out.latency_s}s", file=sys.stderr)
            r.raw = out.text
    if r.raw is None and not args.json:
        print(f"[delegate] escalate: {out.route or 'no route'}; tried {out.tried}", file=sys.stderr)
        r.raw = ""
    return r
