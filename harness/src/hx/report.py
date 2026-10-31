"""Report metrics over the ledger (DESIGN.md §2, Q39). Pure queries; rendering lives elsewhere.

Times are stored as naive UTC and shown in the machine's local zone.
"""

from __future__ import annotations

import re
from collections import defaultdict
from datetime import datetime, timedelta, timezone

IDLE_CAP = timedelta(minutes=30)  # gaps longer than this count as "away", not waiting
CHARS_PER_TOKEN = 4  # rough estimate for tool output (rtk uses the same)
_PLUMBING = {"cd", "set", "export", "echo", "printf", "true", "sleep"}  # never the command of interest
# Tools whose first positional word is a subcommand worth grouping by ("git status", "bd ready").
_SUBCOMMAND_TOOLS = {"git", "bd", "uv", "npm", "npx", "pnpm", "cargo", "go", "docker", "gh", "hx",
                     "pip", "dotnet", "winget", "wsl", "rtk", "opencode", "claude", "codex"}

# A call belongs to the task claimed most recently before it in its session; a close
# ends that attribution (ASOF join over claim/close events).
CALL_TASK = """
SELECT c.*, CASE WHEN st.source = 'claim' THEN st.task_id END AS task_id
FROM (SELECT * FROM call WHERE ts >= TIMESTAMP '{since}') c
ASOF LEFT JOIN session_task st ON c.session_id = st.session_id AND c.ts >= st.ts
"""


def local_offset() -> timedelta:
    return datetime.now().astimezone().utcoffset() or timedelta(0)


def parse_since(spec: str | None, now: datetime | None = None) -> datetime:
    """'7d', '24h', 'all', or an ISO date (local). Returns naive UTC."""
    now = now or datetime.now(timezone.utc).replace(tzinfo=None)
    if not spec or spec == "all":
        return datetime(1970, 1, 1)
    m = re.fullmatch(r"(\d+)([dh])", spec)
    if m:
        n = int(m[1])
        return now - (timedelta(days=n) if m[2] == "d" else timedelta(hours=n))
    return datetime.fromisoformat(spec) - local_offset()


def build(con, since: datetime, offset: timedelta | None = None) -> dict:
    offset = offset if offset is not None else local_offset()
    # Views can't take parameters; `since` is always a datetime we built, never user text.
    con.execute("CREATE OR REPLACE TEMP VIEW ct AS " + CALL_TASK.format(since=since.isoformat(sep=" ")))
    return {
        "totals": _totals(con),
        "by_day": _by_day(con, offset),
        "by_model": _rows(con, """
            SELECT model, provider, count(*) AS calls, sum(output_tokens) AS output_tokens,
                   round(sum(cache_read_tokens) / nullif(sum(input_tokens + cache_read_tokens
                         + cache_write_5m_tokens + cache_write_1h_tokens), 0), 3) AS cache_hit,
                   round(sum(est_usd), 4) AS est_usd
            FROM ct GROUP BY ALL ORDER BY est_usd DESC NULLS LAST"""),
        "by_task": _rows(con, """
            SELECT coalesce(task_id, '(none)') AS task, count(DISTINCT session_id) AS sessions,
                   count(*) AS calls, round(sum(est_usd), 4) AS est_usd,
                   coalesce(task_id IN (SELECT task_id FROM session_task WHERE source = 'close'), false) AS closed
            FROM ct GROUP BY ALL ORDER BY est_usd DESC NULLS LAST"""),
        "by_session": _rows(con, """
            SELECT s.session_id[:8] AS session, coalesce(s.title, '') AS title,
                   (min(ct.ts) + to_seconds(?))::TIMESTAMP(0) AS started, count(*) AS calls,
                   round(sum(ct.est_usd), 4) AS est_usd
            FROM ct JOIN session s USING (session_id) GROUP BY ALL ORDER BY started DESC""",
                            [offset.total_seconds()]),
        "tools": _rows(con, """
            SELECT u.tool, count(*) AS uses,
                   sum(coalesce(r.is_error::INT, 0)) AS errors,
                   sum((r.denied IS NOT NULL)::INT) AS denied,
                   sum(r.result_chars) // ? AS output_tokens_est,
                   round(avg(r.result_chars) / ?) AS avg_tokens
            FROM tool_use u LEFT JOIN tool_result r USING (tool_use_id)
            WHERE u.ts >= ? GROUP BY ALL ORDER BY output_tokens_est DESC NULLS LAST""",
                       [CHARS_PER_TOKEN, CHARS_PER_TOKEN, since]),
        "commands": _commands(con, since),
        "friction": _friction(con, since),
        "time": _time(con, since),
        "quota": _quota(con, offset),
        "pending": ["delegation acceptance (sw-lbm.15)", "tagged outcome rate (sw-lbm.17)"],
    }


def _quota(con, offset: timedelta) -> list[dict]:
    """Latest reading per provider window, with linear burn projection."""
    from hx import quota

    rows = con.execute("""
        SELECT provider, window_name, epoch(ts), used_pct, epoch(resets_at) FROM quota_snapshot
        WHERE resets_at >= (SELECT max(resets_at) - INTERVAL 60 SECOND FROM quota_snapshot q2
                           WHERE q2.provider = quota_snapshot.provider AND q2.window_name = quota_snapshot.window_name)
        ORDER BY provider, window_name, ts""").fetchall()
    by_win: dict = defaultdict(list)
    for prov, win, ts, used, resets in rows:
        by_win[(prov, win)].append(quota.Snapshot(ts, win, used, resets, provider=prov))
    out = []
    local = lambda e: (datetime.fromtimestamp(e, timezone.utc).replace(tzinfo=None) + offset)  # noqa: E731
    for (prov, win), snaps in by_win.items():
        cur = snaps[-1]
        p = quota.project(cur, snaps)
        out.append({"provider": prov, "window": win, "used_pct": round(cur.used_pct, 1),
                    "as_of": local(cur.ts).strftime("%m-%d %H:%M"),
                    "resets": local(cur.resets_at).strftime("%m-%d %H:%M"),
                    "burn_pct_per_h": p.rate_per_h,
                    "projected_full": local(p.full_at).strftime("%m-%d %H:%M") if p.full_at else None,
                    "hits_limit_before_reset": p.will_hit_limit})
    return out


def write_summary(con, path=None) -> dict:
    """Small JSON cache for the status line (which must not open the ledger)."""
    import json
    import time

    from hx.paths import data_dir

    offset = local_offset()
    now_local = datetime.now(timezone.utc).replace(tzinfo=None) + offset
    midnight_utc = now_local.replace(hour=0, minute=0, second=0, microsecond=0) - offset
    today, week = con.execute(
        "SELECT coalesce(sum(est_usd) FILTER (WHERE ts >= ?), 0), coalesce(sum(est_usd) FILTER (WHERE ts >= ?), 0) "
        "FROM call", [midnight_utc, midnight_utc - timedelta(days=6)]).fetchone()
    con.execute("CREATE OR REPLACE TEMP VIEW ct AS " + CALL_TASK.format(since=datetime(1970, 1, 1)))
    t = _totals(con)
    summ = {"generated_at": time.time(), "today_usd": round(today, 4), "week_usd": round(week, 4),
            "usd_per_closed_task": t["usd_per_closed_task"], "tasks_closed": t["tasks_closed"]}
    path = path or data_dir() / "cache" / "summary.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(summ), encoding="utf-8")
    return summ


def _rows(con, sql: str, params: list | None = None) -> list[dict]:
    cur = con.execute(sql, params or [])
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, r)) for r in cur.fetchall()]


def _totals(con) -> dict:
    t = _rows(con, """
        SELECT count(*) AS calls, count(DISTINCT session_id) AS sessions,
               coalesce(sum(input_tokens), 0) AS input_tokens, coalesce(sum(output_tokens), 0) AS output_tokens,
               coalesce(sum(cache_read_tokens), 0) AS cache_read_tokens,
               coalesce(sum(cache_write_5m_tokens + cache_write_1h_tokens), 0) AS cache_write_tokens,
               round(coalesce(sum(est_usd), 0), 4) AS est_usd
        FROM ct""")[0]
    prompt = t["input_tokens"] + t["cache_read_tokens"] + t["cache_write_tokens"]
    t["cache_hit"] = round(t["cache_read_tokens"] / prompt, 3) if prompt else None
    closed = _rows(con, """
        SELECT count(*) AS n, sum(usd) AS usd FROM (
            SELECT task_id, sum(est_usd) AS usd FROM ct
            WHERE task_id IN (SELECT task_id FROM session_task WHERE source = 'close') GROUP BY task_id)""")[0]
    t["tasks_closed"] = closed["n"]
    t["usd_per_closed_task"] = round(closed["usd"] / closed["n"], 4) if closed["n"] else None
    return t


def _by_day(con, offset: timedelta) -> list[dict]:
    return _rows(con, """
        SELECT (ts + to_seconds(?))::DATE AS day, model, count(*) AS calls,
               sum(output_tokens) AS output_tokens, round(sum(est_usd), 4) AS est_usd
        FROM ct GROUP BY ALL ORDER BY day, model""", [offset.total_seconds()])


def command_key(cmd: str) -> str:
    """'cd x && git status --short | head' -> 'git status'. Groups repeat commands for mining."""
    for seg in re.split(r"&&|;|\|\|", cmd):
        words = seg.strip().lstrip("(").split()
        while words and (words[0] in ("time", "env") or re.fullmatch(r"\w+=\S*", words[0])):
            words = words[1:]
        if not words or words[0] in _PLUMBING:
            continue
        name = words[0].rsplit("/", 1)[-1].removesuffix(".exe")
        if name not in _SUBCOMMAND_TOOLS:
            return name
        sub = next((w for w in words[1:] if not w.startswith("-")), "")
        return f"{name} {sub}" if re.fullmatch(r"[a-z][\w-]*", sub) else name
    return cmd.strip().split()[0] if cmd.strip() else ""


def _commands(con, since) -> list[dict]:
    rows = con.execute("""
        SELECT u.command, r.result_chars FROM tool_use u LEFT JOIN tool_result r USING (tool_use_id)
        WHERE u.command IS NOT NULL AND u.ts >= ?""", [since]).fetchall()
    agg: dict[str, list[int]] = defaultdict(lambda: [0, 0])
    for cmd, chars in rows:
        a = agg[command_key(cmd)]
        a[0] += 1
        a[1] += chars or 0
    out = [{"command": k, "uses": u, "output_tokens_est": c // CHARS_PER_TOKEN} for k, (u, c) in agg.items()]
    return sorted(out, key=lambda r: (-r["uses"], -r["output_tokens_est"]))


def _friction(con, since) -> dict:
    ev = dict(con.execute("SELECT kind, count(*) FROM event WHERE ts >= ? GROUP BY kind", [since]).fetchall())
    err, den = con.execute("""
        SELECT coalesce(sum(is_error::INT), 0), coalesce(sum((denied IS NOT NULL)::INT), 0)
        FROM tool_result WHERE ts >= ?""", [since]).fetchone()
    return {"tool_errors": err, "denials": den, "interrupts": ev.get("interrupt", 0),
            "api_errors": ev.get("api_error", 0), "compactions": ev.get("compaction", 0)}


def _time(con, since) -> dict:
    """Agent work vs human wait for main (non-subagent) timelines.

    A turn runs from a human prompt to the last activity before the next prompt.
    Work = prompt -> last activity. Wait = last activity -> next prompt, capped at
    IDLE_CAP (anything longer is 'away').
    """
    rows = con.execute("""
        SELECT session_id, ts, kind FROM (
            SELECT session_id, ts, 'prompt' AS kind FROM event WHERE kind = 'prompt' AND agent_id IS NULL
            UNION ALL SELECT session_id, ts, 'act' FROM call WHERE agent_id IS NULL
            UNION ALL SELECT r.session_id, r.ts, 'act' FROM tool_result r
                JOIN tool_use u USING (tool_use_id) WHERE u.agent_id IS NULL
        ) WHERE ts >= ? ORDER BY session_id, ts""", [since]).fetchall()
    work = wait = away = timedelta(0)
    turns = 0
    by_session: dict[str, list] = defaultdict(list)
    for sid, ts, kind in rows:
        by_session[sid].append((ts, kind))
    for events in by_session.values():
        start = last = None
        for ts, kind in events:
            if kind == "prompt":
                if start is not None:
                    work += last - start
                    gap = ts - last
                    wait += min(gap, IDLE_CAP)
                    away += max(gap - IDLE_CAP, timedelta(0))
                start = last = ts
                turns += 1
            elif start is not None:
                last = ts
        if start is not None:
            work += last - start
    hours = lambda d: round(d.total_seconds() / 3600, 2)  # noqa: E731
    total = work + wait
    return {"turns": turns, "agent_work_h": hours(work), "human_wait_h": hours(wait), "away_h": hours(away),
            "agent_share": round(work / total, 3) if total else None}
