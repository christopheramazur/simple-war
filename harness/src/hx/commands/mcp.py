"""hx mcp: stdio MCP server exposing `delegate` to agent clients (Claude Code .mcp.json, OpenCode).

Minimal JSON-RPC 2.0 over newline-delimited stdio (MCP 2025-06-18), stdlib only.
stdout carries protocol messages only; anything else goes to stderr.
"""

from __future__ import annotations

import json
import sys

from hx.output import Result

HELP = "MCP server (stdio) exposing the delegate tool"
PROTOCOL = "2025-06-18"

TOOLS = [{
    "name": "delegate",
    "description": (
        "Hand a self-contained task to the cheapest model the benchmark routing table trusts with it "
        "(usually the free local Bonsai model). Use for mechanical work: format conversion, "
        "filtering/sorting data, filling schema data, log triage, classification. Returns the model's "
        "output; if needs_review is true, check it before using it. If escalate is true, no trusted "
        "model was available: do the task yourself."),
    "inputSchema": {
        "type": "object",
        "properties": {
            "prompt": {"type": "string", "description": "the complete task, including all input data"},
            "level": {"type": "string", "enum": ["L1", "L2", "L3", "L4", "L5"],
                      "description": "L1 transform, L2 schema data-fill, L3 summarize/classify, "
                                     "L4 code from spec, L5 multi-step repo edit"},
            "task_class": {"type": "string", "description": "routing class, e.g. csv_to_json, log_triage"},
            "size": {"type": "string", "enum": ["s", "m", "l"], "description": "expected output size"},
        },
        "required": ["prompt", "level"],
    },
}]


def _reply(msg_id, result=None, error=None) -> None:
    body = {"jsonrpc": "2.0", "id": msg_id, **({"error": error} if error else {"result": result})}
    sys.stdout.write(json.dumps(body) + "\n")
    sys.stdout.flush()


def _call_delegate(a: dict) -> dict:
    from hx import delegate
    out = delegate.run(a["prompt"], a["level"], a.get("task_class"), a.get("size"))
    meta = {"model": out.model, "route": out.route, "match": out.match, "verdict": out.verdict,
            "needs_review": out.needs_review, "escalate": out.escalate, "latency_s": out.latency_s}
    if out.escalate:
        meta["tried"] = out.tried
        return {"content": [{"type": "text", "text": json.dumps(meta)}], "isError": False}
    return {"content": [{"type": "text", "text": out.text},
                        {"type": "text", "text": json.dumps(meta)}], "isError": False}


def handle(msg: dict) -> None:
    method, msg_id = msg.get("method"), msg.get("id")
    if msg_id is None:  # notification (e.g. notifications/initialized): no reply
        return
    if method == "initialize":
        _reply(msg_id, {"protocolVersion": PROTOCOL, "capabilities": {"tools": {}},
                        "serverInfo": {"name": "hx", "version": "0.1"}})
    elif method == "ping":
        _reply(msg_id, {})
    elif method == "tools/list":
        _reply(msg_id, {"tools": TOOLS})
    elif method == "tools/call":
        p = msg.get("params") or {}
        if p.get("name") != "delegate":
            _reply(msg_id, error={"code": -32602, "message": f"unknown tool {p.get('name')}"})
            return
        try:
            _reply(msg_id, _call_delegate(p.get("arguments") or {}))
        except Exception as e:  # report as a tool error, keep the server up
            _reply(msg_id, {"content": [{"type": "text", "text": f"{type(e).__name__}: {e}"}], "isError": True})
    else:
        _reply(msg_id, error={"code": -32601, "message": f"method not found: {method}"})


def run(args) -> Result:
    for line in sys.stdin:
        if not line.strip():
            continue
        try:
            msg = json.loads(line)
        except ValueError:
            _reply(None, error={"code": -32700, "message": "parse error"})
            continue
        handle(msg)
    r = Result("mcp")
    r.raw = ""
    return r
