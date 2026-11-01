"""OTLP receiver for Claude Code telemetry (DESIGN.md §2, Q20b; sw-lbm.6).

Claude Code exports OpenTelemetry logs (events) and metrics when CLAUDE_CODE_ENABLE_TELEMETRY=1
(set in .claude/settings.json `env`, protocol http/json, delta temporality). This stdlib receiver on
127.0.0.1:4318 appends each payload to data/raw/otel/<day>.jsonl, the durable copy; ingest parses
them. Only what transcripts lack becomes ledger events (no double counting: calls and tokens stay
with the transcript importer):

  api latency, tool run time and success, permission decisions, API errors with status,
  active time, lines of code changed.
"""

from __future__ import annotations

import hashlib
import json
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from hx import paths

HOST, PORT = "127.0.0.1", 4318
MAX_BODY = 20 * 1024 * 1024


def raw_dir() -> Path:
    d = paths.data_dir() / "raw" / "otel"
    d.mkdir(parents=True, exist_ok=True)
    return d


def state_dir() -> Path:
    d = paths.data_dir() / "otel"
    d.mkdir(parents=True, exist_ok=True)
    return d


# ---------------- receiver ----------------

# Account identity Claude Code attaches to every record; not needed here, so never stored.
SCRUB = {"user.email", "user.account_uuid", "user.account_id", "user.id", "organization.id"}


def scrub(node):
    """Drop SCRUB attributes anywhere in an OTLP payload (resource, record and data-point attributes)."""
    if isinstance(node, dict):
        return {k: ([scrub(a) for a in v if not (isinstance(a, dict) and a.get("key") in SCRUB)]
                    if k == "attributes" and isinstance(v, list) else scrub(v)) for k, v in node.items()}
    if isinstance(node, list):
        return [scrub(x) for x in node]
    return node


class Handler(BaseHTTPRequestHandler):
    SIGNALS = {"/v1/logs": "logs", "/v1/metrics": "metrics", "/v1/traces": "traces"}

    def do_GET(self):  # health
        self._reply(200, b'{"ok":true}' if self.path == "/health" else b"{}")

    def do_POST(self):
        signal = self.SIGNALS.get(self.path.split("?")[0])
        n = int(self.headers.get("Content-Length") or 0)
        if not signal or n > MAX_BODY:
            return self._reply(404 if not signal else 413, b"{}")
        body = self.rfile.read(n)
        if "json" not in (self.headers.get("Content-Type") or ""):
            return self._reply(415, b'{"error":"only http/json; set OTEL_EXPORTER_OTLP_PROTOCOL=http/json"}')
        try:
            payload = json.loads(body)
        except ValueError:
            return self._reply(400, b"{}")
        now = datetime.now(timezone.utc)
        line = json.dumps({"ts": now.isoformat(timespec="milliseconds"), "signal": signal, "body": scrub(payload)})
        with (raw_dir() / f"{now:%Y%m%d}.jsonl").open("a", encoding="utf-8", newline="\n") as f:
            f.write(line + "\n")
        self._reply(200, b"{}")

    def _reply(self, code: int, body: bytes):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):  # quiet
        pass


def serve(host: str = HOST, port: int = PORT) -> None:
    ThreadingHTTPServer((host, port), Handler).serve_forever()


def alive(timeout: float = 1) -> bool:
    try:
        with urllib.request.urlopen(f"http://{HOST}:{PORT}/health", timeout=timeout):
            return True
    except (urllib.error.URLError, OSError):
        return False


def start(wait: float = 15) -> tuple[bool, str]:
    import os
    import sys

    from hx import background
    from hx.paths import HARNESS_ROOT
    if alive():
        return True, "already running"
    env = dict(os.environ, PYTHONPATH=str(HARNESS_ROOT / "src"), PYTHONUTF8="1")
    proc = background.spawn([sys.executable, "-m", "hx.cli", "otel", "serve"], HARNESS_ROOT, env,
                            state_dir() / "receiver.log")
    (state_dir() / "receiver.pid").write_text(str(proc.pid))
    deadline = time.time() + wait
    while time.time() < deadline:
        if alive():
            return True, f"started pid {proc.pid} on {HOST}:{PORT}"
        if proc.poll() is not None:
            return False, f"exited with {proc.returncode}; see {state_dir() / 'receiver.log'}"
        time.sleep(0.3)
    return False, "not healthy in time"


def stop() -> str:
    from hx import background
    pf = state_dir() / "receiver.pid"
    if not pf.exists():
        return "not running (no pid file)"
    pid = pf.read_text().strip()
    background.kill_tree(pid)
    pf.unlink(missing_ok=True)
    return f"stopped pid {pid}"


# ---------------- parsing (ingest) ----------------

def _attrs(items) -> dict:
    out = {}
    for a in items or []:
        v = a.get("value") or {}
        val = next((v[k] for k in ("stringValue", "intValue", "doubleValue", "boolValue") if k in v), None)
        if "intValue" in v:
            val = int(val)
        out[a.get("key")] = val
    return out


def _ns_ts(ns) -> datetime | None:
    try:
        return datetime.fromtimestamp(int(ns) / 1e9, timezone.utc).replace(tzinfo=None) if ns and int(ns) else None
    except (TypeError, ValueError):
        return None


def _iso(s) -> datetime | None:
    try:
        return datetime.fromisoformat(str(s).replace("Z", "+00:00")).astimezone(timezone.utc).replace(tzinfo=None)
    except ValueError:
        return None


def _num(x) -> float | None:
    try:
        return float(x)
    except (TypeError, ValueError):
        return None


def _eid(*parts) -> str:
    return "otel:" + hashlib.sha1(json.dumps(parts, default=str, sort_keys=True).encode()).hexdigest()[:20]


# event name -> (ledger kind, value attribute, detail attributes)
LOG_EVENTS = {
    "claude_code.api_request": ("api_latency", "duration_ms", ("model",)),
    "claude_code.tool_result": ("tool_run", "duration_ms", ("tool_name", "success", "tool_use_id")),
    "claude_code.tool_decision": ("tool_decision", None, ("tool_name", "decision", "source", "tool_use_id")),
    "claude_code.api_error": ("api_error_otel", "duration_ms", ("model", "status_code", "error")),
}
METRICS = {"claude_code.active_time.total": "active_s", "claude_code.lines_of_code.count": "lines_changed"}


def parse_line(line: dict) -> list[dict]:
    """Ledger event rows from one raw receiver line."""
    body, out = line.get("body") or {}, []
    if line.get("signal") == "logs":
        for rl in body.get("resourceLogs") or []:
            for sl in rl.get("scopeLogs") or []:
                for rec in sl.get("logRecords") or []:
                    a = _attrs(rec.get("attributes"))
                    name = a.get("event.name") or (rec.get("body") or {}).get("stringValue")
                    name = name if str(name).startswith("claude_code.") else f"claude_code.{name}"
                    spec = LOG_EVENTS.get(name)
                    if not spec:
                        continue
                    kind, vkey, dkeys = spec
                    ts = _iso(a.get("event.timestamp")) or _ns_ts(rec.get("timeUnixNano"))
                    detail = "|".join(f"{k}={a[k]}" for k in dkeys if a.get(k) is not None)
                    out.append({"event_id": _eid(name, a), "session_id": a.get("session.id"), "agent_id": None,
                                "ts": ts, "kind": kind, "value": _num(a.get(vkey)) if vkey else None,
                                "detail": detail[:300] or None})
    elif line.get("signal") == "metrics":
        for rm in body.get("resourceMetrics") or []:
            for sm in rm.get("scopeMetrics") or []:
                for m in sm.get("metrics") or []:
                    kind = METRICS.get(m.get("name"))
                    if not kind:
                        continue
                    for dp in (m.get("sum") or m.get("gauge") or {}).get("dataPoints") or []:
                        a = _attrs(dp.get("attributes"))
                        val = _num(dp.get("asDouble", dp.get("asInt")))
                        detail = "|".join(f"{k}={a[k]}" for k in ("type",) if a.get(k)) or None
                        out.append({"event_id": _eid(m["name"], a, dp.get("startTimeUnixNano"), dp.get("timeUnixNano")),
                                    "session_id": a.get("session.id"), "agent_id": None,
                                    "ts": _ns_ts(dp.get("timeUnixNano")), "kind": kind, "value": val, "detail": detail})
    return out
