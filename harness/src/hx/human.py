"""The owner's inbox: beads waiting on a human, and where an answer goes (hx human).

Waiting on the owner:
  - open beads labelled `needs-human` (agents' sign-off requests) or `human` (`bd human`, swarm incidents);
  - beads labelled `autopilot-blocked` (a headless run stopped for a decision).

An answer always lands in the bead's notes ("OWNER <time AEST>: ..."), which is what any later session reads: autopilot
puts `bd show` in its prompt. Then one of:
  - release: drop the waiting labels and give autopilot its attempts back, so the work continues with the answer;
  - close:   the decision itself was the work; closing unblocks the beads it blocks, and they get the answer too;
  - note:    record it only.
Other beads named in the answer (sw-...) get it as well, and every answer is logged in docs/owner-answers.md.
"""

from __future__ import annotations

import re
from collections.abc import Callable
from dataclasses import dataclass, field

from hx import clock, paths

WAIT_LABELS = ("needs-human", "human", "autopilot-blocked")
LOG = "docs/owner-answers.md"
ACTIONS = ("release", "close", "note")
_BEAD = re.compile(r"\bsw-[0-9a-z]+(?:\.[0-9]+)*\b")
_LOG_HEAD = ("# Owner answers\n\nWritten by `hx human`: each answer the owner gave a bead that was waiting on them, "
             "newest last. The bead notes hold the same text.\n")


def _bd_json(*args: str) -> list[dict]:
    from hx import swarm
    return swarm._bd_json(*args)


def _bd(*args: str):
    from hx import swarm
    return swarm._bd(*args)


@dataclass
class Item:
    id: str
    title: str
    priority: int
    status: str
    kind: str                      # "decision" (needs-human / human) or "blocked" (autopilot-blocked)
    labels: list[str]
    description: str = ""
    notes: str = ""
    blocks: list[dict] = field(default_factory=list)   # [{"id", "title"}] beads that wait on this one


def queue(bd_json: Callable[..., list[dict]] = _bd_json) -> list[Item]:
    """Every bead waiting on the owner, highest priority first."""
    rows = bd_json("list", "--status=open,in_progress,blocked", "--limit", "0")
    out = []
    for r in rows:
        labels = list(r.get("labels") or [])
        if not set(labels) & set(WAIT_LABELS):
            continue
        kind = "decision" if {"needs-human", "human"} & set(labels) else "blocked"
        out.append(Item(r["id"], r.get("title", ""), int(r.get("priority", 4)), r.get("status", ""), kind, labels))
    out.sort(key=lambda i: (i.priority, i.kind != "decision", i.id))
    return out


def load(item: Item, bd_json: Callable[..., list[dict]] = _bd_json) -> Item:
    """Fill in the description, notes and the beads this one blocks."""
    d = (bd_json("show", item.id) or [{}])[0]
    item.description, item.notes = d.get("description") or "", d.get("notes") or ""
    try:
        item.blocks = [{"id": x["id"], "title": x.get("title", "")}
                       for x in bd_json("dep", "list", item.id, "--direction=up", "-t", "blocks")]
    except RuntimeError:
        item.blocks = []
    return item


def default_action(item: Item) -> str:
    """Close a decision that other beads wait on; otherwise hand the work back to the agents."""
    return "close" if item.kind == "decision" and item.blocks else "release"


def mentioned(answer: str, own: str) -> list[str]:
    seen: list[str] = []
    for m in _BEAD.findall(answer):
        if m != own and m not in seen:
            seen.append(m)
    return seen


def reset_autopilot(bead: str, answer: str) -> bool:
    """Give autopilot its attempts back on this bead, so its picker takes it again. True if there was a job."""
    from hx import autopilot as ap
    j = ap.load_job(bead)
    if not j:
        return False
    j.update(attempts=0, outcome="owner_answered", detail=f"owner answered {clock.stamp()}: {answer}"[:1200])
    ap.save_job(j)
    return True


def apply(item: Item, answer: str, action: str, bd: Callable = _bd, reset: Callable[[str, str], bool] = reset_autopilot) -> list[str]:
    """Route `answer` for `item`; returns what was done, one line each."""
    if action not in ACTIONS:
        raise ValueError(f"action must be one of {ACTIONS}")
    answer = answer.strip()
    if not answer:
        raise ValueError("empty answer")
    t = clock.stamp()
    done = []

    def note(bead: str, text: str) -> None:
        r = bd("update", bead, f"--append-notes={text}")
        if getattr(r, "returncode", 0):
            done.append(f"{bead}: note FAILED ({(r.stderr or '').strip()[-120:]})")
        else:
            done.append(f"{bead}: answer added to notes")

    note(item.id, f"OWNER {t}: {answer}")
    for other in mentioned(answer, item.id):
        note(other, f"OWNER {t} (answering {item.id}): {answer}")
    if action == "close":
        for b in item.blocks:
            if b["id"] not in mentioned(answer, item.id):
                note(b["id"], f"OWNER {t} (decided {item.id}, which this waited on): {answer}")
        bd("close", item.id, f"--reason=owner decided: {answer}"[:900])
        done.append(f"{item.id}: closed" + (f"; unblocks {', '.join(b['id'] for b in item.blocks)}" if item.blocks else ""))
    elif action == "release":
        gone = [lb for lb in item.labels if lb in WAIT_LABELS]
        for lb in gone:
            bd("update", item.id, f"--remove-label={lb}")
        if item.status == "in_progress":
            bd("unclaim", item.id)
        again = reset(item.id, answer)
        done.append(f"{item.id}: released to agents (removed {', '.join(gone)})"
                    + ("; autopilot attempts reset" if again else ""))
    return done


def log_answer(item: Item, answer: str, action: str, commit: bool = True) -> str:
    """Append to docs/owner-answers.md in the main checkout and commit just that file. Returns a status line."""
    from hx import swarm
    root = paths.main_root()
    p = root / LOG
    p.parent.mkdir(parents=True, exist_ok=True)
    body = "\n".join("> " + ln for ln in answer.strip().splitlines())
    entry = f"\n## {clock.stamp()} · {item.id} · {action}\n**{item.title}** ({item.kind}, P{item.priority})\n\n{body}\n"
    with swarm.file_lock("git"):
        old = p.read_text(encoding="utf-8") if p.exists() else _LOG_HEAD
        p.write_text(old + entry, encoding="utf-8", newline="")
        if not commit:
            return f"logged in {LOG}"
        swarm.git("add", "--", LOG, cwd=root)
        r = swarm.git("commit", "-q", "-m", f"{item.id}: owner answer ({action}) via hx human", "--", LOG, cwd=root)
    return f"logged in {LOG}" + ("" if not r.returncode else f" (commit failed: {(r.stdout + r.stderr).strip()[-160:]})")
