"""Session tagging (DESIGN.md §3, Q13; sw-lbm.17).

After a session ends, the worker builds a short digest (the human prompts from the raw transcript plus
ledger metrics) and has the routed tagger model (Bonsai, via hx delegate) assign kind / area /
complexity / outcome with a confidence. Friction is computed from the metrics, never judged.
A deterministic share of sessions is re-tagged by a stronger model; agreement measures the tagger.

Tags are raw records in data/raw/tags/<YYYYMM>.jsonl (the ledger stays derived); query them
with DuckDB read_json and join to the ledger on session_id.
"""

from __future__ import annotations

import hashlib
import json
import re
import tomllib
from datetime import datetime, timezone
from pathlib import Path

from hx import paths
from hx.paths import HARNESS_ROOT

TAXONOMY_FILE = HARNESS_ROOT / "config" / "taxonomy.toml"
PROMPT_CHARS = 600
MAX_PROMPTS = 6
REPLY_CHARS = 800


def taxonomy(path: Path | None = None) -> dict:
    return tomllib.loads((path or TAXONOMY_FILE).read_text(encoding="utf-8"))


def tags_dir() -> Path:
    return paths.data_dir() / "raw" / "tags"


def tagged_ids() -> set[tuple[str, str]]:
    """(session_id, role) pairs already tagged."""
    out = set()
    for f in tags_dir().glob("*.jsonl") if tags_dir().exists() else []:
        for line in f.read_text(encoding="utf-8").splitlines():
            if line.strip():
                r = json.loads(line)
                if r.get("valid"):
                    out.add((r["session_id"], r["role"]))
    return out


def is_audited(session_id: str, share: float) -> bool:
    h = int(hashlib.sha256(session_id.encode()).hexdigest()[:8], 16)
    return h % 1000 < share * 1000


# ---------------- digest ----------------

def _opencode_messages(raw_file: Path) -> list[dict]:
    rows = [json.loads(line) for line in raw_file.read_text(encoding="utf-8").splitlines() if line.strip()]
    return [r for r in rows if r.get("kind") == "message"]


def _is_opencode(raw_file: Path) -> bool:
    return raw_file.parent.name == "opencode"


def human_prompts(raw_file: Path) -> list[str]:
    if _is_opencode(raw_file):
        return [m["data"]["text"].strip() for m in _opencode_messages(raw_file)
                if m["type"] == "user" and (m["data"].get("text") or "").strip()]
    out = []
    for line in raw_file.read_text(encoding="utf-8", errors="replace").splitlines():
        try:
            r = json.loads(line)
        except ValueError:
            continue
        if r.get("type") != "user" or r.get("isMeta") or (r.get("origin") or {}).get("kind") != "human":
            continue
        content = (r.get("message") or {}).get("content")
        if isinstance(content, list):
            content = "\n".join(b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text")
        if content and content.strip():
            out.append(content.strip())
    return out


def last_reply(raw_file: Path) -> str:
    """The final assistant text in the transcript: what the outcome is judged on."""
    if _is_opencode(raw_file):
        texts = ["\n".join(b.get("text", "") for b in m["data"].get("content") or [] if b.get("type") == "text")
                 for m in _opencode_messages(raw_file) if m["type"] == "assistant"]
        return next((x.strip() for x in reversed(texts) if x.strip()), "")
    last = ""
    for line in raw_file.read_text(encoding="utf-8", errors="replace").splitlines():
        try:
            r = json.loads(line)
        except ValueError:
            continue
        if r.get("type") == "assistant" and not r.get("isSidechain"):
            content = (r.get("message") or {}).get("content") or []
            text = "\n".join(b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text")
            if text.strip():
                last = text.strip()
    return last


def metrics(con, session_id: str) -> dict:
    q = lambda sql: con.execute(sql, [session_id]).fetchone()  # noqa: E731
    calls, first, last = q("SELECT count(*), min(ts), max(ts) FROM call WHERE session_id = ?")
    tools = con.execute("SELECT tool, count(*) n FROM tool_use WHERE session_id = ? GROUP BY 1 ORDER BY 2 DESC LIMIT 6",
                        [session_id]).fetchall()
    errors, denied = q("SELECT count(*) FILTER (WHERE is_error), count(*) FILTER (WHERE denied IS NOT NULL) "
                       "FROM tool_result WHERE session_id = ?")
    ev = dict(con.execute("SELECT kind, count(*) FROM event WHERE session_id = ? GROUP BY 1", [session_id]).fetchall())
    tasks = [r[0] for r in con.execute("SELECT DISTINCT task_id FROM session_task WHERE session_id = ?", [session_id]).fetchall()]
    n_tools = sum(n for _, n in tools)
    return {
        "calls": calls, "minutes": round((last - first).total_seconds() / 60, 1) if first and last else 0,
        "tools": {t: n for t, n in tools}, "tool_calls": n_tools, "tool_errors": errors, "denied": denied,
        "interrupts": ev.get("interrupt", 0), "api_errors": ev.get("api_error", 0),
        "compactions": ev.get("compaction", 0), "prompts": ev.get("prompt", 0), "tasks": tasks,
    }


def friction(m: dict) -> dict:
    """Computed, not judged: share of tool calls that failed plus weighted interruptions."""
    rate = (m["tool_errors"] + m["denied"]) / m["tool_calls"] if m["tool_calls"] else 0.0
    score = round(rate + 0.1 * m["interrupts"] + 0.05 * m["api_errors"] + 0.05 * m["compactions"], 3)
    return {"score": score, "tool_error_rate": round(rate, 3), "interrupts": m["interrupts"],
            "api_errors": m["api_errors"], "compactions": m["compactions"], "denied": m["denied"]}


def digest(prompts: list[str], m: dict, reply: str = "") -> str:
    pick = prompts if len(prompts) <= MAX_PROMPTS else prompts[:MAX_PROMPTS - 1] + prompts[-1:]
    lines = [f"- {p[:PROMPT_CHARS]}" + ("…" if len(p) > PROMPT_CHARS else "") for p in pick]
    return (f"User prompts ({len(prompts)} total, {len(pick)} shown):\n" + "\n".join(lines) +
            f"\n\nSession stats: {m['minutes']} min, {m['calls']} model calls, tools {m['tools']}, "
            f"{m['tool_errors']} tool errors, {m['interrupts']} interrupts, tasks {m['tasks'] or 'none'}." +
            (f"\n\nFinal assistant reply (end):\n{reply[-REPLY_CHARS:]}" if reply else ""))


def prompt(tax: dict, dig: str) -> str:
    opts = lambda key: "\n".join(f"  {k}: {v}" for k, v in tax[key].items())  # noqa: E731
    return (
        "Tag this coding-agent session for a game project (Godot game 'Simple War' plus its agent harness).\n\n"
        f"kind (pick one):\n{opts('kind')}\n\noutcome (pick one):\n{opts('outcome')}\n\n"
        f"complexity (1-5):\n{opts('complexity')}\n\n"
        "area: 2-4 words naming the system worked on (e.g. 'benchmark routing', 'combat UI').\n"
        "confidence: 0.0-1.0, how sure you are of kind and outcome.\n\n"
        f"{dig}\n\n"
        'Output only JSON: {"kind": "...", "area": "...", "complexity": N, "outcome": "...", "confidence": X}')


def parse(text: str, tax: dict) -> tuple[dict, str | None]:
    """(tag fields, problem or None)."""
    m = re.search(r"\{.*\}", text or "", re.S)
    if not m:
        return {}, "no JSON object"
    try:
        d = json.loads(m.group(0))
    except ValueError as e:
        return {}, f"bad JSON: {e}"
    tag = {"kind": str(d.get("kind", "")).strip().lower(), "area": str(d.get("area", "")).strip()[:60],
           "complexity": d.get("complexity"), "outcome": str(d.get("outcome", "")).strip().lower(),
           "confidence": d.get("confidence")}
    if tag["kind"] not in tax["kind"]:
        return tag, f"kind {tag['kind']!r} not in taxonomy"
    if tag["outcome"] not in tax["outcome"]:
        return tag, f"outcome {tag['outcome']!r} not in taxonomy"
    try:
        tag["complexity"] = int(tag["complexity"])
        tag["confidence"] = max(0.0, min(1.0, float(tag["confidence"])))
    except (TypeError, ValueError):
        return tag, "complexity/confidence not numbers"
    if not 1 <= tag["complexity"] <= 5:
        return tag, "complexity out of range"
    return tag, None


# ---------------- tagging ----------------

def _write(row: dict) -> None:
    d = tags_dir()
    d.mkdir(parents=True, exist_ok=True)
    with (d / f"{datetime.now(timezone.utc):%Y%m}.jsonl").open("a", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(row) + "\n")


def find_raw(session_id: str) -> Path | None:
    from hx.importers import claude_code, opencode
    oc = opencode.raw_root() / f"{session_id}.jsonl"
    return oc if oc.exists() else next(claude_code.raw_root().glob(f"*/{session_id}.jsonl"), None)


def tag_session(session_id: str, con=None, tax: dict | None = None, delegate_run=None, audit_call=None,
                force: bool = False) -> list[dict]:
    """Tag one session (and audit it if it's in the audit share). Returns the rows written."""
    from hx import delegate, ledger
    tax = tax or taxonomy()
    done = set() if force else tagged_ids()
    raw = find_raw(session_id)
    if raw is None:
        raise FileNotFoundError(f"no raw transcript for {session_id} (run hx ingest)")
    own = con is None
    con = con or ledger.read_only()
    try:
        m = metrics(con, session_id)
    finally:
        if own:
            con.close()
    dig = digest(human_prompts(raw), m, last_reply(raw))
    text = prompt(tax, dig)
    base = {"session_id": session_id, "taxonomy_version": tax["version"], "friction": friction(m),
            "minutes": m["minutes"], "calls": m["calls"], "tasks": m["tasks"]}
    rows = []
    if (session_id, "tagger") not in done:
        out = (delegate_run or delegate.run)(text, tax["tag_level"], tax["tag_class"], None)
        tag, problem = parse(out.text, tax) if not out.escalate else ({}, "escalated: no tagger available")
        rows.append({**base, **tag, "role": "tagger", "model": out.model, "valid": problem is None,
                     "problem": problem, "ts": datetime.now(timezone.utc).isoformat(timespec="seconds")})
    if is_audited(session_id, tax["audit_share"]) and (session_id, "audit") not in done:
        from hx.bench import adapters
        call = audit_call or adapters.call
        reply = call({"adapter": "claude-cli", "model": tax["audit_model"]}, delegate.SYSTEM, text, 300)
        tag, problem = parse(reply.text, tax) if not reply.error else ({}, reply.error[:200])
        rows.append({**base, **tag, "role": "audit", "model": tax["audit_model"], "valid": problem is None,
                     "problem": problem, "ts": datetime.now(timezone.utc).isoformat(timespec="seconds")})
    for r in rows:
        _write(r)
    return rows


def untagged_sessions(con) -> list[str]:
    done = {sid for sid, role in tagged_ids() if role == "tagger"}
    ids = [r[0] for r in con.execute("SELECT session_id FROM session ORDER BY session_id").fetchall()]
    return [s for s in ids if s not in done]


def accuracy(rows: list[dict]) -> dict:
    """Agreement between tagger and audit on sessions that have both (valid) tags."""
    by: dict[str, dict] = {}
    for r in rows:
        if r.get("valid"):
            by.setdefault(r["session_id"], {})[r["role"]] = r
    pairs = [(v["tagger"], v["audit"]) for v in by.values() if "tagger" in v and "audit" in v]
    if not pairs:
        return {"pairs": 0}
    n = len(pairs)
    return {"pairs": n,
            "kind_agree": round(sum(t["kind"] == a["kind"] for t, a in pairs) / n, 3),
            "outcome_agree": round(sum(t["outcome"] == a["outcome"] for t, a in pairs) / n, 3),
            "complexity_within_1": round(sum(abs(t["complexity"] - a["complexity"]) <= 1 for t, a in pairs) / n, 3)}


def read_rows() -> list[dict]:
    rows = []
    for f in sorted(tags_dir().glob("*.jsonl")) if tags_dir().exists() else []:
        rows += [json.loads(line) for line in f.read_text(encoding="utf-8").splitlines() if line.strip()]
    return rows
