"""Claude Code transcript importer (DESIGN.md §2, Q20a).

Source: ~/.claude/projects/<project>/<session>.jsonl, plus
<session>/subagents/agent-<id>.jsonl for subagents.

Steps:
1. Copy each changed source file into data/raw/claude-code/ (the durable record;
   Claude Code deletes old transcripts).
2. Parse the raw copy into ledger rows.

The transcript format is undocumented. Notes from inspection (Claude Code 2.1.3xx):
- One API response is written as several `assistant` records, one per content
  block, all sharing message.id. Usage repeats on each, so dedupe by message.id
  and keep the largest output_tokens.
- `<synthetic>` model records are client-generated, e.g. API error stubs.
- Tool results arrive in later `user` records as `tool_result` content blocks.
"""

from __future__ import annotations

import json
import os
import re
import shutil
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

from hx.paths import data_dir

CLIENT = "claude-code"
_BD_RE = re.compile(r"\bbd\s+(?:update\s+(?P<claim>[\w.\-]+)\b[^\n]*--claim|close\s+(?P<close>[\w.\-]+))")
_INTERRUPT = "[Request interrupted by user"
SHELL_TOOLS = {"Bash", "PowerShell"}


def source_root() -> Path:
    return Path(os.environ.get("HX_CLAUDE_PROJECTS") or Path.home() / ".claude" / "projects")


def raw_root() -> Path:
    return data_dir() / "raw" / CLIENT


@dataclass
class Parsed:
    sessions: dict[str, dict] = field(default_factory=dict)
    calls: dict[str, dict] = field(default_factory=dict)
    tool_uses: list[dict] = field(default_factory=list)
    tool_results: list[dict] = field(default_factory=list)
    events: list[dict] = field(default_factory=list)
    tasks: list[dict] = field(default_factory=list)


# ---------- step 1: raw copies ----------

def sync_raw(src: Path | None = None, dst: Path | None = None) -> list[Path]:
    """Copy new/changed transcripts to the raw store. Returns raw files that changed.

    A source that shrank (rewritten or truncated) never overwrites the larger raw
    copy; it is stored beside it, and message-id dedupe absorbs the overlap.
    """
    src, dst = src or source_root(), dst or raw_root()
    changed = []
    for f in src.rglob("*.jsonl"):
        target = dst / f.relative_to(src)
        st = f.stat()
        if target.exists():
            tst = target.stat()
            if tst.st_size == st.st_size and tst.st_mtime_ns >= st.st_mtime_ns:
                continue
            if st.st_size < tst.st_size:
                target = target.with_name(f"{target.stem}.{st.st_mtime_ns}.jsonl")
                if target.exists():
                    continue
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(f, target)
        changed.append(target)
    return changed


# ---------- step 2: parse ----------

def _ts(s: str | None) -> datetime | None:
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).replace(tzinfo=None)
    except ValueError:
        return None


def _text_len(content) -> int:
    if isinstance(content, str):
        return len(content)
    if isinstance(content, list):
        return sum(len(b.get("text", "")) if isinstance(b, dict) else 0 for b in content)
    return 0


def _project(raw_file: Path, root: Path) -> str:
    try:
        return raw_file.relative_to(root).parts[0]
    except (ValueError, IndexError):
        return ""


def parse_file(raw_file: Path, root: Path | None = None, out: Parsed | None = None) -> Parsed:
    root = root or raw_root()
    out = out or Parsed()
    project = _project(raw_file, root)
    file_agent = raw_file.stem.removeprefix("agent-").split(".")[0] if raw_file.stem.startswith("agent-") else None
    with raw_file.open(encoding="utf-8", errors="replace") as fh:
        for n, line in enumerate(fh):
            try:
                r = json.loads(line)
            except json.JSONDecodeError:
                continue
            _record(r, out, project, file_agent, f"{raw_file.name}:{n}")
    return out


def _record(r: dict, out: Parsed, project: str, file_agent: str | None, where: str) -> None:
    sid = r.get("sessionId") or r.get("session_id")
    if not sid:
        return
    t = r.get("type")
    agent = r.get("agentId") or file_agent
    ts = _ts(r.get("timestamp"))

    s = out.sessions.setdefault(sid, {"session_id": sid, "client": CLIENT, "project": project, "cwd": None,
                                      "git_branch": None, "title": None, "entrypoint": None,
                                      "client_version": None})
    if not agent:  # subagent records would overwrite the parent's context
        for key, col in (("cwd", "cwd"), ("gitBranch", "git_branch"), ("entrypoint", "entrypoint"),
                         ("version", "client_version")):
            if r.get(key):
                s[col] = r[key]
    if t == "custom-title":
        s["title"] = r.get("customTitle")
    elif t == "assistant":
        _assistant(r, out, sid, agent, ts, where)
    elif t == "user":
        _user(r, out, sid, agent, ts)
    elif t == "system":
        sub = r.get("subtype")
        if sub == "turn_duration":
            _event(out, r.get("uuid") or where, sid, agent, ts, "turn", r.get("durationMs"))
        elif sub and "compact" in sub:
            _event(out, r.get("uuid") or where, sid, agent, ts, "compaction", None, sub)


def _event(out, eid, sid, agent, ts, kind, value=None, detail=None):
    out.events.append({"event_id": f"{kind}:{eid}", "session_id": sid, "agent_id": agent, "ts": ts,
                       "kind": kind, "value": value, "detail": detail})


def _assistant(r, out, sid, agent, ts, where):
    m = r.get("message") or {}
    if r.get("isApiErrorMessage") or r.get("error"):
        _event(out, r.get("uuid") or where, sid, agent, ts, "api_error", None, str(r.get("error") or ""))
    model = m.get("model")
    mid = m.get("id")
    if not mid or model == "<synthetic>":
        return
    u = m.get("usage") or {}
    cc = u.get("cache_creation") or {}
    w1h = cc.get("ephemeral_1h_input_tokens")
    w5m = cc.get("ephemeral_5m_input_tokens")
    if w1h is None and w5m is None:  # older usage shape: treat all writes as 5m
        w5m, w1h = u.get("cache_creation_input_tokens", 0), 0
    row = {
        "call_id": mid, "session_id": sid, "agent_id": agent, "client": CLIENT,
        "provider": None, "model": model, "ts": ts,
        "input_tokens": u.get("input_tokens", 0) or 0,
        "output_tokens": u.get("output_tokens", 0) or 0,
        "cache_read_tokens": u.get("cache_read_input_tokens", 0) or 0,
        "cache_write_5m_tokens": w5m or 0, "cache_write_1h_tokens": w1h or 0,
        "thinking_tokens": (u.get("output_tokens_details") or {}).get("thinking_tokens") or 0,
        "stop_reason": m.get("stop_reason"), "est_usd": None, "source": "transcript",
    }
    prev = out.calls.get(mid)
    if prev is None or row["output_tokens"] >= prev["output_tokens"]:
        if prev is not None:
            row["ts"] = prev["ts"] or ts  # keep first-seen time
        out.calls[mid] = row
    for b in m.get("content") or []:
        if isinstance(b, dict) and b.get("type") == "tool_use":
            inp = b.get("input") or {}
            cmd = inp.get("command") if b.get("name") in SHELL_TOOLS else None
            out.tool_uses.append({
                "tool_use_id": b.get("id"), "call_id": mid, "session_id": sid, "agent_id": agent, "ts": ts,
                "tool": b.get("name"), "input_chars": len(json.dumps(inp)),
                "command": cmd[:500] if isinstance(cmd, str) else None,
            })
            if isinstance(cmd, str):
                for mt in _BD_RE.finditer(cmd):
                    task = mt["claim"] or mt["close"]
                    out.tasks.append({"session_id": sid, "task_id": task, "ts": ts,
                                      "source": "claim" if mt["claim"] else "close"})


def _user(r, out, sid, agent, ts):
    content = (r.get("message") or {}).get("content")
    blocks = content if isinstance(content, list) else [{"type": "text", "text": content or ""}]
    for b in blocks:
        if not isinstance(b, dict):
            continue
        if b.get("type") == "tool_result":
            out.tool_results.append({
                "tool_use_id": b.get("tool_use_id"), "session_id": sid, "ts": ts,
                "result_chars": _text_len(b.get("content")), "is_error": bool(b.get("is_error")),
                "denied": r.get("toolDenialKind"),
            })
        elif b.get("type") == "text":
            text = b.get("text", "")
            if text.startswith(_INTERRUPT):
                _event(out, r.get("uuid"), sid, agent, ts, "interrupt")
            elif (r.get("origin") or {}).get("kind") == "human" and not r.get("isMeta"):
                _event(out, r.get("uuid"), sid, agent, ts, "prompt", len(text))
