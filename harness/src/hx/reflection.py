"""Weekly reflection: proposals only (DESIGN.md §9, Q29; sw-lbm.19).

Modelled on harness2's propose -> probe -> compose:
  evidence  mechanical facts for the window (ledger, tags, delegate/gateway logs, bench, mining)
  propose   a stronger model reads the evidence and proposes at most MAX_PROPOSALS changes,
            each citing the evidence it rests on
  probe     drop proposals without evidence, outside the allowed areas, or duplicating open tasks
  compose   file the survivors as bd tasks (label `reflection`) and keep the whole run as a raw record

Nothing is applied: auto-apply waits for the eval set (§9). Runs as a throttled worker job (weekly)
and as `hx reflect`.
"""

from __future__ import annotations

import json
import re
import subprocess
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path

from hx import paths

MAX_PROPOSALS = 5
INTERVAL_DAYS = 7
MODEL = "claude-sonnet-5-5"
AREAS = {"harness", "routing", "tagging", "mining", "prompts", "docs", "workflow", "game", "budget"}
DUP_OVERLAP = 0.6  # word overlap with an open task's title that counts as a duplicate
# Actions that stay with the user (AGENTS.md §6). Mentioning a $0 budget is fine; raising one is not.
MONEY = re.compile(r"\b(?:(?:raise|increase|lift|bump)\w*\s+(?:\w+\s+){0,3}(?:budget|spend cap)"
                   r"|purchas\w*|buy\w*\s+credits?|pay for|credit card|top.?up"
                   r"|delet\w*\s+(?:the\s+)?(?:ledger|history|transcripts?))")


def out_dir() -> Path:
    d = paths.data_dir() / "raw" / "reflection"
    d.mkdir(parents=True, exist_ok=True)
    return d


def last_run() -> datetime | None:
    runs = sorted(out_dir().glob("*.json"))
    return datetime.fromisoformat(json.loads(runs[-1].read_text(encoding="utf-8"))["ts"]) if runs else None


def _jsonl(d: Path, since: datetime) -> list[dict]:
    rows = []
    for f in sorted(d.glob("*.jsonl")) if d.exists() else []:
        for line in f.read_text(encoding="utf-8").splitlines():
            try:
                r = json.loads(line)
            except ValueError:
                continue
            ts = r.get("ts")
            if ts and datetime.fromisoformat(ts) >= since:
                rows.append(r)
    return rows


# ---------------- evidence ----------------

def evidence(con, since: datetime) -> dict:
    """Mechanical facts for the window. Every proposal must cite one of these keys."""
    s = since.replace(tzinfo=None)
    q = lambda sql, *a: con.execute(sql, [s, *a]).fetchall()  # noqa: E731
    ev: dict = {"window": f"since {since.date()}"}
    ev["spend"] = [{"client": c, "provider": p, "calls": n, "usd": round(u or 0, 2)} for c, p, n, u in q(
        "SELECT client, provider, count(*), sum(est_usd) FROM call WHERE ts >= ? GROUP BY 1, 2 ORDER BY 4 DESC NULLS LAST")]
    from hx import providers
    ev["billing"] = {pid: ("free account: usd is list price, not charged" if p.billing == "none" else p.billing)
                     for pid, p in providers.load().items() if p.kind in ("api", "local")}
    ev["failing_tools"] = [{"tool": t, "calls": n, "errors": e} for t, n, e in q("""
        SELECT u.tool, count(*), count(*) FILTER (WHERE r.is_error) FROM tool_use u JOIN tool_result r USING (tool_use_id)
        WHERE u.ts >= ? GROUP BY 1 HAVING count(*) FILTER (WHERE r.is_error) >= 3 ORDER BY 3 DESC LIMIT 8""")]
    from hx.mining import shape
    failing = Counter()
    for cmd, in q("""SELECT u.command FROM tool_use u JOIN tool_result r USING (tool_use_id)
                     WHERE u.ts >= ? AND r.is_error AND u.command IS NOT NULL"""):
        failing[shape(cmd)] += 1
    ev["failing_commands"] = [{"shape": k, "errors": n} for k, n in failing.most_common(8) if n >= 2]
    ev["events"] = dict(q("SELECT kind, count(*) FROM event WHERE ts >= ? GROUP BY 1"))

    from hx import tagging
    tags = [r for r in _rows_since(tagging.read_rows(), since) if r.get("valid")]
    tagger = [r for r in tags if r["role"] == "tagger"]
    ev["sessions_by_kind"] = dict(Counter(r["kind"] for r in tagger))
    ev["high_friction_sessions"] = [{"session": r["session_id"][:14], "kind": r["kind"], "area": r["area"],
                                     "outcome": r["outcome"], "friction": r["friction"]}
                                    for r in sorted(tagger, key=lambda r: -r["friction"]["score"])[:5]
                                    if r["friction"]["score"] >= 0.2]
    ev["tag_audit"] = tagging.accuracy(tags)

    dl = _jsonl(paths.data_dir() / "raw" / "delegate", since)
    skips = Counter(t.get("skipped") or t.get("error", "")[:80] for r in dl for t in r.get("tried", []) if not t.get("ok"))
    ev["delegate"] = {"calls": len(dl), "escalated": sum(r["escalate"] for r in dl),
                      "served_by": dict(Counter(r["model"] for r in dl if r.get("model"))),
                      "fallback_reasons": dict(skips.most_common(5))}
    gw = _jsonl(paths.data_dir() / "raw" / "gateway", since)
    ev["gateway"] = {"calls": len(gw), "failures": dict(Counter(
        f"{r.get('provider')}: {(r.get('error') or '')[:70]}" for r in gw if r.get("status") != "success").most_common(5))}

    from hx import mining
    st = mining.load_state()
    ev["mining"] = {"filed": len(st["filed"]), "top_unfiled": [
        {"shape": c["shape"], "uses": c["uses"], "sessions": c["sessions"]}
        for c in mining.candidates(con, 1, 5) if c["shape"] not in st["filed"]][:5]}
    return ev


def _rows_since(rows: list[dict], since: datetime) -> list[dict]:
    return [r for r in rows if r.get("ts") and datetime.fromisoformat(r["ts"]) >= since]


# ---------------- propose ----------------

def prompt(ev: dict, open_titles: list[str]) -> str:
    return (
        "You review one week of an AI-agent harness for a Godot game project. The harness logs every model "
        "call (ledger), tags sessions, routes cheap tasks to a local model (hx delegate), and mines repeated "
        "commands into CLI verbs. Find friction and waste in the evidence and propose concrete changes.\n\n"
        f"EVIDENCE (JSON):\n{json.dumps(ev, indent=1, default=str)}\n\n"
        f"ALREADY OPEN TASKS (don't repeat these):\n" + "\n".join(f"- {t}" for t in open_titles[:60]) + "\n\n"
        f"Rules: at most {MAX_PROPOSALS} proposals, fewer is fine, none is fine. Each must cite evidence keys "
        "from the JSON above and quote the numbers it rests on. Prefer small, testable changes. Never propose "
        "spending money, raising budgets, deleting history, or posting externally.\n"
        f"area must be one of: {', '.join(sorted(AREAS))}.\n"
        'Output only JSON: {"proposals": [{"title": "...", "area": "...", "evidence": ["key", ...], '
        '"why": "...", "change": "...", "verify": "how to tell it worked"}]}')


def parse(text: str) -> list[dict]:
    m = re.search(r"\{.*\}", text or "", re.S)
    try:
        d = json.loads(m.group(0)) if m else {}
    except ValueError:
        return []
    return [p for p in d.get("proposals", []) if isinstance(p, dict)]


# ---------------- probe ----------------

def _words(s: str) -> set[str]:
    return {w for w in re.findall(r"[a-z0-9]+", s.lower()) if len(w) > 2}


def _asks_for_money(text: str) -> bool:
    """A MONEY phrase that isn't negated ("do not raise the budgets" is fine)."""
    return any(not re.search(r"\b(not|n't|never|no|without)\s+(\w+\s+)?$", text[max(0, m.start() - 20):m.start()])
               for m in MONEY.finditer(text))


def probe(props: list[dict], ev: dict, open_titles: list[str]) -> list[dict]:
    """Annotate each proposal with `rejected` (reason) or None."""
    out = []
    for p in props[:MAX_PROPOSALS]:
        title = str(p.get("title", "")).strip()
        # "delegate.fallback_reasons" cites the delegate section
        cites = [str(c) for c in p.get("evidence") or [] if re.split(r"[.\[]", str(c))[0] in ev]
        reason = None
        if not title or not p.get("change"):
            reason = "no title or change"
        elif not cites:
            reason = "cites no evidence key"
        elif p.get("area") not in AREAS:
            reason = f"area {p.get('area')!r} not allowed"
        elif _asks_for_money(json.dumps(p).lower()):
            reason = "touches money or history (needs the user)"
        else:
            w = _words(title)
            for t in open_titles:
                ow = _words(t)
                if w and ow and len(w & ow) / min(len(w), len(ow)) >= DUP_OVERLAP:
                    reason = f"duplicates open task: {t[:60]}"
                    break
        out.append({**p, "title": title, "evidence": cites, "rejected": reason})
    return out


# ---------------- compose ----------------

def open_tasks() -> list[str]:
    p = subprocess.run(["bd", "list", "--status=open", "--json", "--limit", "0"], capture_output=True, text=True,
                       encoding="utf-8", errors="replace", cwd=paths.repo_root())
    try:
        return [x["title"] for x in json.loads(p.stdout or "[]")]
    except ValueError:
        return []


def _bd_create(p: dict) -> str | None:
    body = (f"Weekly reflection proposal (DESIGN.md §9, proposals only).\n\nWhy: {p.get('why', '')}\n\n"
            f"Change: {p['change']}\n\nVerify: {p.get('verify', '')}\n\nEvidence: {', '.join(p['evidence'])}")
    r = subprocess.run(["bd", "create", p["title"][:120], "-t", "task", "-p", "3", "-l", f"harness,reflection,{p['area']}",
                        "-d", body, "--silent"], capture_output=True, text=True, encoding="utf-8", errors="replace",
                       cwd=paths.repo_root())
    return r.stdout.strip() or None if r.returncode == 0 else None


def run(con, force: bool = False, file: bool = True, call=None, create=_bd_create, titles=None, now=None) -> dict:
    now = now or datetime.now(timezone.utc)
    last = last_run()
    if not force and last and now - last < timedelta(days=INTERVAL_DAYS):
        return {"skipped": f"last reflection {last.date()}; runs every {INTERVAL_DAYS} days"}
    since = now - timedelta(days=INTERVAL_DAYS)
    ev = evidence(con, since)
    titles = open_tasks() if titles is None else titles
    if call is None:
        from hx.bench import adapters
        call = adapters.call
    reply = call({"adapter": "claude-cli", "model": MODEL}, "You are a careful engineering reviewer.",
                 prompt(ev, titles), 600)
    props = probe(parse(reply.text), ev, titles) if not reply.error else []
    for p in props:
        p["issue"] = create(p) if file and not p["rejected"] else None
    record = {"ts": now.isoformat(timespec="seconds"), "model": MODEL, "error": reply.error,
              "evidence": ev, "proposals": props}
    (out_dir() / f"{now:%Y%m%d-%H%M%S}.json").write_text(json.dumps(record, indent=1, default=str), encoding="utf-8")
    return record
