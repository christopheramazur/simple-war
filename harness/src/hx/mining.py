"""Repetitive-task mining (DESIGN.md §5, Q26; sw-lbm.18).

Groups the shell commands agents ran (ledger tool_use) into shapes ("uv run && git commit"),
keeps shapes repeated across sessions, and files each new one as a bd task proposing an hx verb.
The local model (via hx delegate) names the verb; without it the shape itself is the title.
Each filed shape keeps its baseline cost so `hx mine --report` can show the verb's savings later.

Runs as a throttled post-session worker job (every MIN_INTERVAL_H at most) and as `hx mine`.
"""

from __future__ import annotations

import json
import re
import subprocess
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

from hx import paths
from hx.report import CHARS_PER_TOKEN, command_key

MIN_SESSIONS = 3
MIN_USES = 5
MAX_FILED_PER_RUN = 3
MIN_INTERVAL_H = 6
# Single agent primitives: repeating them is normal work, not a missing tool.
PRIMITIVES = {"ls", "cat", "grep", "rg", "sed", "awk", "find", "head", "tail", "echo", "printf", "wc", "cd",
              "mkdir", "rm", "mv", "cp", "touch", "sleep", "python", "python3", "node", "bash", "sh", "pwd"}
NAV = {"cd", "pushd", "popd", "export", "set", "source"}
VALUE_FLAGS = {"--project", "--with", "--python", "--from", "-p", "--directory", "--package"}
WRAPPERS = {"uv run", "uvx", "npx", "bunx", "pipx run"}
_HX = re.compile(r"(?:^|[\s/\\])hx(?:\.exe)?\s+([a-z][\w-]*)")


def state_file() -> Path:
    d = paths.data_dir() / "mining"
    d.mkdir(parents=True, exist_ok=True)
    return d / "state.json"


def load_state() -> dict:
    f = state_file()
    return json.loads(f.read_text(encoding="utf-8")) if f.exists() else {"filed": {}, "last_run": None}


def save_state(s: dict) -> None:
    state_file().write_text(json.dumps(s, indent=1), encoding="utf-8")


def shape(cmd: str) -> str:
    """Ordered distinct command keys of a compound command; pipes and plumbing dropped."""
    keys: list[str] = []
    for seg in re.split(r"&&|;|\|\||\n", cmd or ""):
        seg = seg.split("|", 1)[0]
        if not seg.strip() or seg.strip().startswith("#"):
            continue
        k = command_key(seg)
        if k in NAV:
            continue
        if k in WRAPPERS:  # "uv run pytest", not just "uv run"
            k = f"{k} {_wrapped(seg, k)}".strip()
        if k and k not in keys:
            keys.append(k)
    return " && ".join(keys)


def _wrapped(seg: str, wrapper: str) -> str:
    """The program a wrapper runs: first positional word after it, skipping flags and their values."""
    words = seg.split()
    last = wrapper.split()[-1]
    i = words.index(last) + 1 if last in words else len(words)
    while i < len(words):
        w = words[i]
        if w.startswith("-"):
            i += 1 if "=" in w or w not in VALUE_FLAGS else 2
            continue
        return w.replace("\\", "/").rsplit("/", 1)[-1]
    return ""


def hx_verb(cmd: str) -> str | None:
    from hx.cli import VERBS  # only real verbs: "from hx import x" in a python snippet is not one
    return next((v for v in _HX.findall(cmd or "") if v in VERBS), None)


def candidates(con, min_sessions: int = MIN_SESSIONS, min_uses: int = MIN_USES) -> list[dict]:
    rows = con.execute("""
        SELECT u.session_id, u.command, coalesce(u.input_chars, 0), coalesce(r.result_chars, 0)
        FROM tool_use u LEFT JOIN tool_result r USING (tool_use_id) WHERE u.command IS NOT NULL""").fetchall()
    agg: dict[str, dict] = defaultdict(lambda: {"uses": 0, "sessions": set(), "chars": 0, "example": ""})
    for sid, cmd, inp, res in rows:
        if hx_verb(cmd):
            continue
        s = shape(cmd)
        if not s or s in PRIMITIVES:
            continue
        a = agg[s]
        a["uses"] += 1
        a["sessions"].add(sid)
        a["chars"] += inp + res
        if len(cmd) < len(a["example"]) or not a["example"]:
            a["example"] = cmd[:300]
    out = [{"shape": s, "uses": a["uses"], "sessions": len(a["sessions"]),
            "tokens_per_use": a["chars"] // CHARS_PER_TOKEN // a["uses"], "example": a["example"]}
           for s, a in agg.items() if len(a["sessions"]) >= min_sessions and a["uses"] >= min_uses]
    return sorted(out, key=lambda c: (-c["sessions"], -c["uses"] * c["tokens_per_use"]))


def verb_usage(con) -> list[dict]:
    rows = con.execute("""
        SELECT u.command, coalesce(r.result_chars, 0) FROM tool_use u LEFT JOIN tool_result r USING (tool_use_id)
        WHERE u.command LIKE '%hx%'""").fetchall()
    agg: dict[str, list[int]] = defaultdict(lambda: [0, 0])
    for cmd, chars in rows:
        v = hx_verb(cmd)
        if v:
            agg[v][0] += 1
            agg[v][1] += chars
    return sorted(({"verb": v, "uses": u, "tokens_per_use": c // CHARS_PER_TOKEN // u} for v, (u, c) in agg.items()),
                  key=lambda r: -r["uses"])


def propose(c: dict, delegate_run=None) -> dict:
    """Verb name + one-line purpose from the routed local model; falls back to the shape."""
    from hx import delegate
    text = ("An agent repeatedly runs this shell command shape in a Godot game repo with a Python CLI "
            f"called hx.\nShape: {c['shape']}\nExample: {c['example']}\nUses: {c['uses']} in "
            f"{c['sessions']} sessions.\nPropose one hx subcommand that would replace it. Output only JSON: "
            '{"verb": "hx <name> [args]", "purpose": "<one sentence>"}')
    out = (delegate_run or delegate.run)(text, "L3", None, "s")
    m = re.search(r"\{.*\}", out.text or "", re.S)
    try:
        d = json.loads(m.group(0)) if m and not out.escalate else {}
    except ValueError:
        d = {}
    return {"verb": str(d.get("verb") or "")[:60], "purpose": str(d.get("purpose") or "")[:200], "model": out.model}


def _bd_create(title: str, body: str) -> str | None:
    p = subprocess.run(["bd", "create", title, "-t", "task", "-p", "3", "-l", "harness,mined", "-d", body, "--silent"],
                       capture_output=True, text=True, encoding="utf-8", errors="replace", cwd=paths.repo_root())
    return p.stdout.strip() or None if p.returncode == 0 else None


def run(con, file: bool = True, force: bool = False, delegate_run=None, create=_bd_create, now=None) -> dict:
    now = now or datetime.now(timezone.utc)
    st = load_state()
    if not force and st.get("last_run") and now - datetime.fromisoformat(st["last_run"]) < timedelta(hours=MIN_INTERVAL_H):
        return {"skipped": f"ran less than {MIN_INTERVAL_H}h ago", "filed": []}
    cands = candidates(con)
    new = [c for c in cands if c["shape"] not in st["filed"]]
    filed = []
    if file:
        for c in new[:MAX_FILED_PER_RUN]:
            prop = propose(c, delegate_run)
            title = f"hx verb candidate: {prop['verb'] or c['shape']}"[:120]
            body = (f"Mined repeated command shape (DESIGN.md §5): `{c['shape']}`\n"
                    f"{c['uses']} uses in {c['sessions']} sessions, ~{c['tokens_per_use']} tokens per use.\n"
                    f"Example: {c['example']}\n"
                    + (f"Proposed by {prop['model']}: {prop['verb']}: {prop['purpose']}\n" if prop["verb"] else "")
                    + "Decide: build the verb, or close as not worth it. Savings show in `hx mine --report`.")
            issue = create(title, body)
            if issue:
                st["filed"][c["shape"]] = {"issue": issue, "baseline_tokens_per_use": c["tokens_per_use"],
                                           "verb": prop["verb"], "filed_at": now.isoformat(timespec="seconds")}
                filed.append({**c, "issue": issue, "verb": prop["verb"]})
    st["last_run"] = now.isoformat(timespec="seconds")
    save_state(st)
    return {"candidates": len(cands), "new": len(new), "filed": filed}
