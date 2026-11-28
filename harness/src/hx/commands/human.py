"""hx human: the beads waiting on you, one at a time; type an answer and hx routes it.

  hx human                                  walk the queue interactively
  hx human --list                           just list what is waiting
  hx human answer <id> "text" [--then release|close|note] [--no-commit]   answer one without prompts

Waiting = open beads labelled needs-human or human, and beads labelled autopilot-blocked. An answer goes into the
bead's notes (which autopilot and any later session read), into other beads it names (sw-...), and into
docs/owner-answers.md. Then: release (drop the waiting labels, reset autopilot's attempts so it picks the bead up
again), close (the decision was the work: closing unblocks what it blocks, which get the answer too) or note only.
"""

from __future__ import annotations

import argparse
import sys
import textwrap

from hx import human
from hx.output import FAIL, OK, WARN, Check, Result

HELP = "the beads waiting on you: read each, type an answer, and hx routes it to the bead, its dependents and autopilot"


def add_args(p) -> None:
    p.add_argument("--list", action="store_true", help="list what is waiting and exit")
    p.add_argument("--no-commit", action="store_true", help=f"log to {human.LOG} without committing it")
    sub = p.add_subparsers(dest="action", metavar="[answer]")
    a = sub.add_parser("answer", help="answer one bead without prompts")
    a.add_argument("bead")
    a.add_argument("text")
    a.add_argument("--then", choices=human.ACTIONS, help="default: close a decision others wait on, else release")
    a.add_argument("--no-commit", action="store_true", default=argparse.SUPPRESS)


def _clip(text: str, lines: int, width: int = 110) -> str:
    out = []
    for para in text.strip().splitlines():
        out.extend(textwrap.wrap(para, width) or [""])
    more = len(out) - lines
    return "\n".join("  " + ln for ln in out[:lines]) + (f"\n  … {more} more lines (:show)" if more > 0 else "")


def _last_note(notes: str) -> str:
    """The latest entry of the notes: from the last line that starts a stamped entry."""
    lines = notes.strip().splitlines()
    for i in range(len(lines) - 1, -1, -1):
        if lines[i].split(" ", 1)[0] in ("autopilot", "swarm", "OWNER", "ESCALATE", "BLOCKED", "CHECKPOINT:"):
            return "\n".join(lines[i:])
    return "\n".join(lines[-6:])


def _show(i: human.Item, n: int, total: int) -> None:
    print(f"\n{'═' * 100}\n[{n}/{total}] {i.id}  P{i.priority}  {i.kind}  ({i.status}; {', '.join(i.labels)})\n{i.title}")
    if i.description:
        print("\nDescription:\n" + _clip(i.description, 14))
    if i.notes:
        print("\nLatest note:\n" + _clip(_last_note(i.notes), 12))
    if i.blocks:
        print("\nWaiting on this: " + "; ".join(f"{b['id']} {b['title'][:60]}" for b in i.blocks))


def _read_answer() -> str | None:
    """Lines until an empty one. '' = skip, None = quit."""
    print("\nYour answer (end with an empty line). Empty = skip · :show = whole bead · :q = quit")
    lines: list[str] = []
    while True:
        try:
            ln = input("> " if not lines else "  ")
        except EOFError:
            return None if not lines else "\n".join(lines)
        if not lines and ln.strip() == ":q":
            return None
        if not lines and ln.strip() == ":show":
            return ":show"
        if not ln.strip():
            return "\n".join(lines)
        lines.append(ln)


def _ask_action(i: human.Item) -> str | None:
    d = human.default_action(i)
    hint = {"release": "r = release to agents", "close": "c = close as decided", "note": "n = note only"}
    opts = " · ".join(("[" + hint[a] + "]") if a == d else hint[a] for a in human.ACTIONS)
    while True:
        try:
            v = input(f"Then? {opts} · x = discard: ").strip().lower()
        except EOFError:
            return None
        if not v:
            return d
        for a in human.ACTIONS:
            if v in (a, a[0]):
                return a
        if v in ("x", "discard"):
            return None


def _route(i: human.Item, answer: str, action: str, commit: bool) -> list[str]:
    done = human.apply(i, answer, action)
    try:
        done.append(human.log_answer(i, answer, action, commit=commit))
    except Exception as e:  # the bead got it; the log is secondary
        done.append(f"log failed: {e}")
    return done


def run(args) -> Result:
    r = Result("human")
    if getattr(args, "action", None) == "answer":
        items = {x.id: x for x in human.queue()}
        i = items.get(args.bead)
        if not i:
            r.checks.append(Check("bead", FAIL, f"{args.bead} is not waiting on you (no needs-human/human/autopilot-blocked label)"))
            return r
        human.load(i)
        done = _route(i, args.text, args.then or human.default_action(i), not args.no_commit)
        r.data["done"] = done
        r.checks.append(Check("answered", OK, "; ".join(done)))
        return r

    items = human.queue()
    if args.list or not items or not sys.stdin.isatty():
        r.checks.append(Check("waiting", OK if not items else WARN,
                    f"{len(items)} bead(s) waiting on you" + ("" if sys.stdin.isatty() or args.list else
                                                              " (not a terminal: use `hx human answer <id> \"...\"`)")))
        r.tables["waiting"] = [{"id": i.id, "P": i.priority, "kind": i.kind, "title": i.title[:80]} for i in items]
        return r

    answered = skipped = 0
    for n, i in enumerate(items, 1):
        human.load(i)
        _show(i, n, len(items))
        while (ans := _read_answer()) == ":show":
            print(human._bd("show", i.id).stdout)
        if ans is None:
            break
        if not ans.strip():
            skipped += 1
            continue
        action = _ask_action(i)
        if action is None:
            print("  discarded")
            skipped += 1
            continue
        for line in _route(i, ans, action, not args.no_commit):
            print("  ✓ " + line)
        answered += 1
    r.checks.append(Check("session", OK, f"{answered} answered, {skipped} skipped, {len(items) - answered - skipped} left"))
    return r
