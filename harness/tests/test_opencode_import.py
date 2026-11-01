import json
import sqlite3

from hx import tagging
from hx.importers import opencode

SESSION_SQL = ("CREATE TABLE session_v2 (id TEXT, project_id TEXT, parent_id TEXT, directory TEXT, title TEXT, "
               "version TEXT, cost REAL, tokens_input INT, tokens_output INT, agent TEXT, model TEXT, "
               "time_created INT, time_updated INT, idle_outcome TEXT)")
MSG_SQL = "CREATE TABLE session_message (id TEXT, session_id TEXT, type TEXT, seq INT, time_created INT, data TEXT)"
CRED_SQL = "CREATE TABLE credential (id TEXT, value TEXT)"

ASSISTANT = {
    "model": {"id": "bonsai/nothink", "providerID": "hx"}, "finish": "tool-calls", "cost": 0,
    "tokens": {"input": 10, "output": 5, "reasoning": 2, "cache": {"read": 100, "write": 0}},
    "content": [
        {"type": "text", "text": "Running tests."},
        {"type": "tool", "id": "t1", "name": "shell", "time": {"created": 1793000001000, "completed": 1793000002000},
         "state": {"status": "completed", "input": {"command": "uv run pytest"},
                   "content": [{"type": "text", "text": "1 failed"}], "metadata": {"exit": 1}}},
    ],
}


def make_db(path, updated=1793000009000):
    con = sqlite3.connect(path)
    for sql in (SESSION_SQL, MSG_SQL, CRED_SQL):
        con.execute(sql)
    con.execute("INSERT INTO credential VALUES ('c', 'SECRET-TOKEN')")
    con.execute("INSERT INTO session_v2 VALUES ('ses_1', 'p', NULL, 'C:/x/simple-war', 'Fix tests', '2.2.0', 0, 10, 5, "
                "NULL, NULL, 1793000000000, ?, 'succeeded')", [updated])
    con.executemany("INSERT INTO session_message VALUES (?, 'ses_1', ?, ?, ?, ?)", [
        ("m1", "user", 1, 1793000000500, json.dumps({"text": "make the tests pass"})),
        ("m2", "assistant", 2, 1793000001000, json.dumps(ASSISTANT)),
        ("m3", "compaction", 3, 1793000003000, json.dumps({"status": "failed"})),
    ])
    con.commit()
    con.close()


def test_export_parse_and_no_credentials(tmp_path):
    db = tmp_path / "opencode.db"
    make_db(db)
    raw = tmp_path / "raw" / "opencode"
    assert [f.name for f in opencode.export(db, raw)] == ["ses_1.jsonl"]
    assert opencode.export(db, raw) == []  # unchanged session is not rewritten
    assert "SECRET-TOKEN" not in (raw / "ses_1.jsonl").read_text()
    p = opencode.parse_file(raw / "ses_1.jsonl")
    assert p.sessions["ses_1"]["project"] == "simple-war"
    call = p.calls["m2"]
    assert (call["source"], call["input_tokens"], call["cache_read_tokens"], call["thinking_tokens"]) == \
           ("opencode-gateway", 10, 100, 2)
    assert p.tool_uses[0]["command"] == "uv run pytest"
    assert p.tool_results[0]["is_error"] is True and p.tool_results[0]["result_chars"] == 8
    assert sorted(e["kind"] for e in p.events) == ["compaction", "prompt"]


def test_tagging_reads_opencode_raw(tmp_path):
    db = tmp_path / "opencode.db"
    make_db(db)
    raw = tmp_path / "raw" / "opencode"
    opencode.export(db, raw)
    f = raw / "ses_1.jsonl"
    assert tagging.human_prompts(f) == ["make the tests pass"]
    assert tagging.last_reply(f) == "Running tests."
