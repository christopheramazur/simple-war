import json
import threading
import urllib.request
from http.server import ThreadingHTTPServer

from hx import otel


def attr(k, v):
    key = "intValue" if isinstance(v, int) and not isinstance(v, bool) else "stringValue"
    return {"key": k, "value": {key: v if key == "intValue" else str(v)}}


LOGS = {"resourceLogs": [{"resource": {"attributes": [attr("service.name", "claude-code")]}, "scopeLogs": [{"logRecords": [
    {"body": {"stringValue": "claude_code.api_request"}, "attributes": [
        attr("event.name", "api_request"), attr("session.id", "s1"), attr("user.email", "me@example.com"),
        attr("event.timestamp", "2026-11-01T01:27:03.120Z"), attr("model", "claude-haiku-5-5"),
        attr("duration_ms", "1965"), attr("input_tokens", 2)]},
    {"body": {"stringValue": "claude_code.tool_result"}, "attributes": [
        attr("event.name", "tool_result"), attr("session.id", "s1"), attr("tool_name", "Bash"),
        attr("success", "false"), attr("duration_ms", "482"), attr("tool_use_id", "toolu_1"),
        attr("event.timestamp", "2026-11-01T01:27:04Z")]},
    {"body": {"stringValue": "claude_code.user_prompt"}, "attributes": [attr("session.id", "s1")]},
]}]}]}
METRICS = {"resourceMetrics": [{"scopeMetrics": [{"metrics": [
    {"name": "claude_code.active_time.total", "sum": {"aggregationTemporality": 1, "dataPoints": [
        {"asDouble": 5.744, "timeUnixNano": "1793496426543000000", "attributes": [attr("session.id", "s1"), attr("type", "cli")]}]}},
    {"name": "claude_code.token.usage", "sum": {"dataPoints": [{"asInt": "77", "attributes": [attr("session.id", "s1")]}]}},
]}]}]}


def test_parse_keeps_only_what_transcripts_lack():
    rows = otel.parse_line({"signal": "logs", "body": LOGS}) + otel.parse_line({"signal": "metrics", "body": METRICS})
    kinds = {r["kind"]: r for r in rows}
    assert set(kinds) == {"api_latency", "tool_run", "active_s"}  # no prompt, no token usage (transcripts have those)
    assert kinds["api_latency"]["value"] == 1965 and kinds["api_latency"]["session_id"] == "s1"
    assert "tool_use_id=toolu_1" in kinds["tool_run"]["detail"] and "success=false" in kinds["tool_run"]["detail"]
    assert kinds["active_s"]["value"] == 5.744
    again = otel.parse_line({"signal": "logs", "body": LOGS})
    assert [r["event_id"] for r in again] == [r["event_id"] for r in rows[:2]]  # stable ids: re-import is a no-op


def test_scrub_removes_identity_everywhere():
    s = json.dumps(otel.scrub(LOGS))
    assert "me@example.com" not in s and "user.email" not in s and "session.id" in s


def test_receiver_writes_scrubbed_raw(tmp_path, monkeypatch):
    monkeypatch.setenv("HX_DATA_DIR", str(tmp_path))
    srv = ThreadingHTTPServer(("127.0.0.1", 0), otel.Handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:{srv.server_address[1]}"
    try:
        req = urllib.request.Request(url + "/v1/logs", data=json.dumps(LOGS).encode(),
                                     headers={"Content-Type": "application/json"})
        assert urllib.request.urlopen(req).status == 200
        bad = urllib.request.Request(url + "/v1/logs", data=b"\x00", headers={"Content-Type": "application/x-protobuf"})
        try:
            urllib.request.urlopen(bad)
            raise AssertionError("protobuf should be refused")
        except urllib.error.HTTPError as e:
            assert e.code == 415
    finally:
        srv.shutdown()
    lines = [json.loads(x) for f in (tmp_path / "raw" / "otel").glob("*.jsonl") for x in f.read_text().splitlines()]
    assert len(lines) == 1 and lines[0]["signal"] == "logs" and "me@example.com" not in json.dumps(lines)
