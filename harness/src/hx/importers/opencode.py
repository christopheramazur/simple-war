"""OpenCode 2.x importer (DESIGN.md §2; sw-lbm.7).

OpenCode keeps sessions in SQLite (~/.local/share/opencode/opencode.db). Step 1 exports each changed
session (session_v2 row + session_message rows, nothing else: that DB also holds account tokens and
credentials) to data/raw/opencode/<session_id>.jsonl, the durable copy. Step 2 parses those files
into the same ledger tables as Claude Code.

Calls OpenCode routed through our gateway (provider "hx") are also logged by the gateway itself
(client "gateway", no session); they get source "opencode-gateway" so reports can tell them apart.
"""

from __future__ import annotations

import json
import os
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

from hx.importers.claude_code import Parsed
from hx.paths import data_dir

CLIENT = "opencode"
SESSION_COLS = ["id", "project_id", "parent_id", "directory", "title", "version", "cost", "tokens_input",
                "tokens_output", "agent", "model", "time_created", "time_updated", "idle_outcome"]


def db_path() -> Path:
    return Path(os.environ.get("HX_OPENCODE_DB") or Path.home() / ".local" / "share" / "opencode" / "opencode.db")


def raw_root() -> Path:
    return data_dir() / "raw" / CLIENT


def export(db: Path | None = None, dst: Path | None = None) -> list[Path]:
    """Write a raw JSONL per session whose time_updated moved since the last export."""
    db, dst = db or db_path(), dst or raw_root()
    if not db.exists():
        return []
    dst.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(f"file:{db.as_posix()}?mode=ro", uri=True, timeout=10)
    con.row_factory = sqlite3.Row
    written = []
    try:
        for s in con.execute(f"SELECT {', '.join(SESSION_COLS)} FROM session_v2"):
            f = dst / f"{s['id']}.jsonl"
            if f.exists() and _first(f).get("time_updated") == s["time_updated"]:
                continue
            msgs = con.execute("SELECT id, type, seq, time_created, data FROM session_message "
                               "WHERE session_id = ? ORDER BY seq", [s["id"]]).fetchall()
            lines = [json.dumps({"kind": "session", **dict(s)})]
            lines += [json.dumps({"kind": "message", "id": m["id"], "type": m["type"], "seq": m["seq"],
                                  "time_created": m["time_created"], "data": json.loads(m["data"])}) for m in msgs]
            tmp = f.with_suffix(".tmp")
            tmp.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
            tmp.replace(f)
            written.append(f)
    finally:
        con.close()
    return written


def _first(f: Path) -> dict:
    with f.open(encoding="utf-8") as fh:
        try:
            return json.loads(fh.readline())
        except ValueError:
            return {}


def _ts(ms) -> datetime | None:
    return datetime.fromtimestamp(ms / 1000, timezone.utc).replace(tzinfo=None) if ms else None


def _text_len(content) -> int:
    return sum(len(b.get("text", "")) for b in content or [] if isinstance(b, dict))


def parse_file(f: Path) -> Parsed:
    out = Parsed()
    sid = None
    for line in f.read_text(encoding="utf-8").splitlines():
        r = json.loads(line)
        if r["kind"] == "session":
            sid = r["id"]
            directory = (r.get("directory") or "").replace("\\", "/")
            out.sessions[sid] = {"session_id": sid, "client": CLIENT, "project": directory.rsplit("/", 1)[-1] or None,
                                 "cwd": directory or None, "git_branch": None, "title": r.get("title"),
                                 "entrypoint": "opencode", "client_version": r.get("version")}
            continue
        d, mid, ts = r["data"], r["id"], _ts(r["time_created"])
        if r["type"] == "user":
            out.events.append({"event_id": mid, "session_id": sid, "agent_id": None, "ts": ts, "kind": "prompt",
                               "value": len(d.get("text") or ""), "detail": None})
        elif r["type"] == "compaction":
            out.events.append({"event_id": mid, "session_id": sid, "agent_id": None, "ts": ts, "kind": "compaction",
                               "value": None, "detail": d.get("status")})
        elif r["type"] == "assistant":
            _assistant(out, sid, mid, ts, d)
    return out


def _assistant(out: Parsed, sid: str, mid: str, ts, d: dict) -> None:
    model = d.get("model") or {}
    tok = d.get("tokens") or {}
    cache = tok.get("cache") or {}
    via_gateway = model.get("providerID") == "hx"
    if d.get("error"):
        out.events.append({"event_id": f"err:{mid}", "session_id": sid, "agent_id": None, "ts": ts, "kind": "api_error",
                           "value": None, "detail": str(d["error"].get("message"))[:300]})
    if tok:
        out.calls[mid] = {
            "call_id": mid, "session_id": sid, "agent_id": d.get("agent"), "client": CLIENT,
            "provider": model.get("providerID"), "model": model.get("id"), "ts": ts,
            "input_tokens": tok.get("input") or 0, "output_tokens": tok.get("output") or 0,
            "cache_read_tokens": cache.get("read") or 0, "cache_write_5m_tokens": cache.get("write") or 0,
            "cache_write_1h_tokens": 0, "thinking_tokens": tok.get("reasoning") or 0,
            "stop_reason": d.get("finish"), "est_usd": d.get("cost") or 0.0,
            "source": "opencode-gateway" if via_gateway else "opencode"}
    for b in d.get("content") or []:
        if not isinstance(b, dict) or b.get("type") != "tool":
            continue
        st = b.get("state") or {}
        inp = st.get("input") or {}
        meta = st.get("metadata") or {}
        tts = _ts((b.get("time") or {}).get("created")) or ts
        out.tool_uses.append({"tool_use_id": b.get("id"), "call_id": mid, "session_id": sid, "agent_id": None,
                              "ts": tts, "tool": b.get("name"), "input_chars": len(json.dumps(inp)),
                              "command": inp.get("command") if isinstance(inp.get("command"), str) else None})
        if st.get("status") in ("completed", "error", "denied"):
            out.tool_results.append({
                "tool_use_id": b.get("id"), "session_id": sid,
                "ts": _ts((b.get("time") or {}).get("completed")) or tts,
                "result_chars": _text_len(st.get("content")),
                "is_error": st.get("status") == "error" or (meta.get("exit") not in (None, 0)),
                "denied": "denied" if st.get("status") == "denied" else None})
