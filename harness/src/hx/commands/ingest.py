"""hx ingest: copy new client transcripts to the raw store and load them into the ledger."""

from __future__ import annotations

from datetime import datetime, timezone

from hx import ledger, pricing, quota, report
from hx.importers import claude_code, opencode
from hx.output import OK, WARN, Check, Result

HELP = "Import new agent transcripts into the ledger (incremental; --rebuild re-reads all raw copies)"


def add_args(p) -> None:
    p.add_argument("--rebuild", action="store_true", help="drop and rebuild every ledger table from data/raw/")


def run(args) -> Result:
    r = Result("ingest")
    copied = claude_code.sync_raw()
    exported = opencode.export()
    con = ledger.connect(rebuild=args.rebuild)
    try:
        parsed_files = _import_claude_code(con) + _import_opencode(con)
        quota_rows = _import_quota(con)
        gateway_rows = _import_gateway(con)
        _import_ab_arms(con)
        otel_rows = _import_otel(con)
        mark_gateway_duplicates(con)
        unpriced = reprice(con)
        report.write_summary(con)
        r.data.update({
            "copied_to_raw": len(copied) + len(exported),
            "files_parsed": parsed_files,
            "quota_snapshots": quota_rows,
            "gateway_calls": gateway_rows,
            "otel_events": otel_rows,
            **_totals(con),
        })
        if unpriced:
            r.checks.append(Check("pricing", WARN, "no price for: " + ", ".join(unpriced)))
        else:
            r.checks.append(Check("pricing", OK))
    finally:
        con.close()
    return r


def _import_claude_code(con) -> int:
    root = claude_code.raw_root()
    if not root.exists():
        return 0
    seen = {p: (s, m) for p, s, m in con.execute("SELECT raw_path, size, mtime_ns FROM import_state").fetchall()}
    count = 0
    for f in sorted(root.rglob("*.jsonl")):
        key, st = f.relative_to(root.parent).as_posix(), f.stat()
        if seen.get(key) == (st.st_size, st.st_mtime_ns):
            continue
        p = claude_code.parse_file(f, root)
        _merge_sessions(con, list(p.sessions.values()))
        ledger.upsert(con, "call", list(p.calls.values()))
        ledger.upsert(con, "tool_use", p.tool_uses)
        ledger.upsert(con, "tool_result", p.tool_results)
        ledger.upsert(con, "event", p.events)
        ledger.upsert(con, "session_task", p.tasks)
        ledger.upsert(con, "import_state", [{"raw_path": key, "size": st.st_size, "mtime_ns": st.st_mtime_ns,
                                             "imported_at": datetime.now(timezone.utc).replace(tzinfo=None)}])
        count += 1
    return count


def _import_otel(con) -> int:
    """Claude Code OTel payloads (hx otel receiver) -> event rows; only data transcripts lack."""
    import json

    from hx import otel
    root = otel.raw_dir()
    seen = {p: (s, m) for p, s, m in con.execute("SELECT raw_path, size, mtime_ns FROM import_state").fetchall()}
    n = 0
    for f in sorted(root.glob("*.jsonl")):
        key, st = f"otel/{f.name}", f.stat()
        if seen.get(key) == (st.st_size, st.st_mtime_ns):
            continue
        rows = []
        for line in f.read_text(encoding="utf-8").splitlines():
            try:
                rows += otel.parse_line(json.loads(line))
            except (json.JSONDecodeError, KeyError, TypeError):
                continue
        ledger.upsert(con, "event", list({r["event_id"]: r for r in rows}.values()))
        ledger.upsert(con, "import_state", [{"raw_path": key, "size": st.st_size, "mtime_ns": st.st_mtime_ns,
                                             "imported_at": datetime.now(timezone.utc).replace(tzinfo=None)}])
        n += len(rows)
    return n


def _import_ab_arms(con) -> int:
    """A/B arms written by client hooks (e.g. harness/bin/rtk-hook) -> event kind 'ab_<experiment>'."""
    import json

    from hx.paths import data_dir
    rows = []
    for f in (data_dir() / "raw").glob("*/arms.jsonl"):
        exp = f.parent.name
        for line in f.read_text(encoding="utf-8").splitlines():
            try:
                x = json.loads(line)
            except json.JSONDecodeError:
                continue
            ts = datetime.fromisoformat(x["ts"].replace("Z", "+00:00")).replace(tzinfo=None)
            rows.append({"event_id": f"ab_{exp}:{x['session_id']}", "session_id": x["session_id"], "agent_id": None,
                         "ts": ts, "kind": f"ab_{exp}", "value": float(x[exp]),
                         "detail": "forced" if x.get("forced") else None})
    ledger.upsert(con, "event", rows)
    return len(rows)


def mark_gateway_duplicates(con) -> int:
    """OpenCode calls routed through our gateway are logged twice: by OpenCode (session attributed,
    source 'opencode-gateway') and by the gateway (no session). Mark the gateway copy 'gateway-dup'
    so reports count each call once. Same model and output tokens; the gateway's prompt tokens are
    OpenCode's input + cache read; timestamps within 2 minutes. Idempotent."""
    return con.execute("""
        UPDATE call SET source = 'gateway-dup' WHERE call_id IN (
            SELECT g.call_id FROM call g JOIN call o
              ON o.source = 'opencode-gateway' AND g.model = o.model AND g.output_tokens = o.output_tokens
             AND g.input_tokens = o.input_tokens + o.cache_read_tokens
             AND abs(epoch(g.ts) - epoch(o.ts)) <= 120
            WHERE g.client = 'gateway' AND g.source = 'gateway')""").fetchone()[0]


def _import_opencode(con) -> int:
    root = opencode.raw_root()
    if not root.exists():
        return 0
    seen = {p: (s, m) for p, s, m in con.execute("SELECT raw_path, size, mtime_ns FROM import_state").fetchall()}
    count = 0
    for f in sorted(root.glob("*.jsonl")):
        key, st = f"{opencode.CLIENT}/{f.name}", f.stat()
        if seen.get(key) == (st.st_size, st.st_mtime_ns):
            continue
        p = opencode.parse_file(f)
        _merge_sessions(con, list(p.sessions.values()))
        ledger.upsert(con, "call", list(p.calls.values()))
        ledger.upsert(con, "tool_use", p.tool_uses)
        ledger.upsert(con, "tool_result", p.tool_results)
        ledger.upsert(con, "event", p.events)
        ledger.upsert(con, "import_state", [{"raw_path": key, "size": st.st_size, "mtime_ns": st.st_mtime_ns,
                                             "imported_at": datetime.now(timezone.utc).replace(tzinfo=None)}])
        count += 1
    return count


def _import_quota(con) -> int:
    """Load quota logs. They are small and append-only, so re-read whole files that changed."""
    root = quota.log_path().parent
    if not root.exists():
        return 0
    seen = {p: (s, m) for p, s, m in con.execute("SELECT raw_path, size, mtime_ns FROM import_state").fetchall()}
    n = 0
    for f in sorted(root.glob("*.jsonl")):
        key, st = f"quota/{f.name}", f.stat()
        if seen.get(key) == (st.st_size, st.st_mtime_ns):
            continue
        snaps = quota.read_tail(f, max_bytes=st.st_size + 1)
        ledger.upsert(con, "quota_snapshot", [
            {"provider": s.provider, "window_name": s.window, "ts": _utc(s.ts), "used_pct": s.used_pct,
             "resets_at": _utc(s.resets_at), "session_id": s.session_id} for s in snaps])
        ledger.upsert(con, "import_state", [{"raw_path": key, "size": st.st_size, "mtime_ns": st.st_mtime_ns,
                                             "imported_at": datetime.now(timezone.utc).replace(tzinfo=None)}])
        n += len(snaps)
    return n


def _import_gateway(con) -> int:
    """Gateway calls -> `call` (success) or `event` (failure / budget refusal)."""
    import json
    from hx.gateway import budget
    root = budget.log_dir()
    if not root.exists():
        return 0
    seen = {p: (s, m) for p, s, m in con.execute("SELECT raw_path, size, mtime_ns FROM import_state").fetchall()}
    n = 0
    for f in sorted(root.glob("*.jsonl")):
        key, st = f"gateway/{f.name}", f.stat()
        if seen.get(key) == (st.st_size, st.st_mtime_ns):
            continue
        calls, events = [], []
        for i, line in enumerate(f.read_text(encoding="utf-8").splitlines()):
            try:
                x = json.loads(line)
            except json.JSONDecodeError:
                continue
            ts = datetime.fromisoformat(x["ts"]).astimezone(timezone.utc).replace(tzinfo=None)
            cid = x.get("call_id") or f"gw:{f.stem}:{i}"
            if x.get("status") == "success":
                calls.append({
                    "call_id": cid, "session_id": None, "agent_id": x.get("caller"), "client": "gateway",
                    "provider": x.get("provider"), "model": x.get("model_group"), "ts": ts,
                    "input_tokens": x.get("prompt_tokens") or 0, "output_tokens": x.get("completion_tokens") or 0,
                    "cache_read_tokens": 0, "cache_write_5m_tokens": 0, "cache_write_1h_tokens": 0,
                    "thinking_tokens": 0, "stop_reason": None, "est_usd": x.get("cost_usd") or 0.0,
                    "source": "gateway"})
            else:
                events.append({"event_id": f"gateway_{x.get('status')}:{cid}", "session_id": None,
                               "agent_id": x.get("caller"), "ts": ts, "kind": f"gateway_{x.get('status')}",
                               "value": None, "detail": f"{x.get('provider')} {x.get('model_group')}: {x.get('error')}"})
        ledger.upsert(con, "call", calls)
        ledger.upsert(con, "event", events)
        ledger.upsert(con, "import_state", [{"raw_path": key, "size": st.st_size, "mtime_ns": st.st_mtime_ns,
                                             "imported_at": datetime.now(timezone.utc).replace(tzinfo=None)}])
        n += len(calls)
    return n


def _utc(epoch: float) -> datetime:
    return datetime.fromtimestamp(epoch, timezone.utc).replace(tzinfo=None)


def _merge_sessions(con, rows: list[dict]) -> None:
    """Upsert that never replaces a known value with NULL (sessions span several files)."""
    if not rows:
        return
    cols = list(rows[0])
    updates = ", ".join(f"{c} = COALESCE(EXCLUDED.{c}, session.{c})" for c in cols if c != "session_id")
    con.executemany(
        f"INSERT INTO session ({', '.join(cols)}) VALUES ({', '.join('?' * len(cols))}) "
        f"ON CONFLICT (session_id) DO UPDATE SET {updates}",
        [[r[c] for c in cols] for r in rows],
    )


def reprice(con) -> list[str]:
    """Recompute provider and est_usd for every call from the current price table.
    Returns models with no price."""
    prices = pricing.load()
    rows = con.execute(
        "SELECT call_id, model, input_tokens, cache_write_5m_tokens, cache_write_1h_tokens, "
        "cache_read_tokens, output_tokens FROM call"
    ).fetchall()
    updates, unpriced = [], set()
    for cid, model, *toks in rows:
        price = pricing.match(prices, model)
        if price is None:
            unpriced.add(model)
            continue  # keep whatever the source recorded (e.g. gateway provider + LiteLLM cost)
        tokens = dict(zip(pricing.CATEGORIES, toks))
        updates.append([price.provider, pricing.estimate(price, tokens), cid])
    if updates:
        con.executemany("UPDATE call SET provider = ?, est_usd = ? WHERE call_id = ?", updates)
    con.execute("UPDATE call SET provider = 'unknown' WHERE provider IS NULL")
    unpriced_rows = {m for (m,) in con.execute("SELECT DISTINCT model FROM call WHERE est_usd IS NULL").fetchall()}
    return sorted(m for m in unpriced & unpriced_rows if m)


def _totals(con) -> dict:
    sessions, calls, inp, out, cr, cw, usd = con.execute(
        "SELECT (SELECT count(*) FROM session), count(*), sum(input_tokens), sum(output_tokens), "
        "sum(cache_read_tokens), sum(cache_write_5m_tokens + cache_write_1h_tokens), sum(est_usd) FROM call "
        "WHERE source IS DISTINCT FROM 'gateway-dup'"
    ).fetchone()
    return {
        "sessions": sessions,
        "calls": calls,
        "tokens": f"in {inp or 0:,} / out {out or 0:,} / cache read {cr or 0:,} / cache write {cw or 0:,}",
        "est_usd": round(usd or 0, 4),
    }
