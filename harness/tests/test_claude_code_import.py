import json
import os

import pytest

from hx.cli import main
from hx.importers import claude_code as cc

SID = "sess-1"


def usage(out, inp=3, cr=100, w1h=50):
    return {"input_tokens": inp, "output_tokens": out, "cache_read_input_tokens": cr,
            "cache_creation_input_tokens": w1h, "output_tokens_details": {"thinking_tokens": 7},
            "cache_creation": {"ephemeral_1h_input_tokens": w1h, "ephemeral_5m_input_tokens": 0}}


def assistant(mid, blocks, out, ts="2026-10-31T01:00:00Z", model="claude-opus-5-5", **extra):
    return {"type": "assistant", "sessionId": SID, "timestamp": ts, "uuid": f"u-{mid}-{out}",
            "message": {"id": mid, "model": model, "content": blocks, "usage": usage(out),
                        "stop_reason": "tool_use"}, **extra}


MAIN = [
    {"type": "user", "sessionId": SID, "uuid": "p1", "timestamp": "2026-10-31T00:59:00Z",
     "cwd": "C:\\repo", "gitBranch": "main", "entrypoint": "cli", "version": "2.1.309",
     "origin": {"kind": "human"}, "message": {"content": [{"type": "text", "text": "do the thing"}]}},
    # One response written as two records (thinking, then tool_use); usage grows.
    assistant("msg_A", [{"type": "thinking", "thinking": "..."}], 10),
    assistant("msg_A", [{"type": "tool_use", "id": "tu1", "name": "Bash",
                         "input": {"command": "bd update sw-lbm.3 --claim && ls"}}], 40,
              ts="2026-10-31T01:00:02Z"),
    {"type": "user", "sessionId": SID, "uuid": "r1", "timestamp": "2026-10-31T01:00:05Z",
     "message": {"content": [{"type": "tool_result", "tool_use_id": "tu1", "content": "x" * 120,
                              "is_error": True}]}},
    assistant("msg_S", [{"type": "text", "text": "API Error"}], 0, model="<synthetic>",
              isApiErrorMessage=True, error="rate_limit"),
    {"type": "user", "sessionId": SID, "uuid": "i1", "timestamp": "2026-10-31T01:01:00Z",
     "message": {"content": [{"type": "text", "text": "[Request interrupted by user]"}]}},
    {"type": "system", "subtype": "turn_duration", "durationMs": 1234, "sessionId": SID,
     "uuid": "t1", "timestamp": "2026-10-31T01:01:01Z"},
    {"type": "custom-title", "customTitle": "Harness work", "sessionId": SID},
]
SUB = [assistant("msg_B", [{"type": "text", "text": "report"}], 5, model="claude-haiku-5-5",
                 agentId="agent9", cwd="C:\\elsewhere")]


def write(path, records):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(r) + "\n" for r in records) + "not json\n", encoding="utf-8")


@pytest.fixture
def env(tmp_path, monkeypatch):
    src = tmp_path / "projects"
    write(src / "proj" / f"{SID}.jsonl", MAIN)
    write(src / "proj" / SID / "subagents" / "agent-agent9.jsonl", SUB)
    monkeypatch.setenv("HX_CLAUDE_PROJECTS", str(src))
    monkeypatch.setenv("HX_DATA_DIR", str(tmp_path / "data"))
    return src


def test_parse_dedupes_and_extracts(env):
    cc.sync_raw()
    p = cc.Parsed()
    for f in sorted(cc.raw_root().rglob("*.jsonl")):
        cc.parse_file(f, out=p)
    assert set(p.calls) == {"msg_A", "msg_B"}  # synthetic skipped
    a = p.calls["msg_A"]
    assert a["output_tokens"] == 40 and a["cache_write_1h_tokens"] == 50 and a["thinking_tokens"] == 7
    assert str(a["ts"]) == "2026-10-31 01:00:00"  # first-seen time kept
    assert p.calls["msg_B"]["agent_id"] == "agent9"
    assert p.tool_uses[0]["command"].startswith("bd update")
    assert p.tool_results[0]["is_error"] is True and p.tool_results[0]["result_chars"] == 120
    assert p.tasks == [{"session_id": SID, "task_id": "sw-lbm.3", "ts": p.tool_uses[0]["ts"], "source": "claim"}]
    kinds = sorted(e["kind"] for e in p.events)
    assert kinds == ["api_error", "interrupt", "prompt", "turn"]
    s = p.sessions[SID]
    assert s["title"] == "Harness work" and s["cwd"] == "C:\\repo"  # subagent cwd ignored


def test_sync_raw_incremental_and_shrink(env):
    assert len(cc.sync_raw()) == 2
    assert cc.sync_raw() == []
    main_src = env / "proj" / f"{SID}.jsonl"
    main_src.write_text(json.dumps(MAIN[0]) + "\n", encoding="utf-8")
    os.utime(main_src, ns=(10**19, 10**19))
    changed = cc.sync_raw()
    assert len(changed) == 1 and changed[0].name != f"{SID}.jsonl"  # stored beside, not overwritten
    assert (cc.raw_root() / "proj" / f"{SID}.jsonl").stat().st_size > main_src.stat().st_size


def test_ingest_end_to_end(env, capsys):
    assert main(["ingest", "--json"]) == 0
    d = json.loads(capsys.readouterr().out)["data"]
    assert d["calls"] == 2 and d["sessions"] == 1 and d["files_parsed"] == 2
    assert d["est_usd"] > 0
    # Second run is a no-op; --rebuild re-reads everything to the same totals.
    main(["ingest", "--json"])
    assert json.loads(capsys.readouterr().out)["data"]["files_parsed"] == 0
    main(["ingest", "--rebuild", "--json"])
    d2 = json.loads(capsys.readouterr().out)["data"]
    assert d2["files_parsed"] == 2 and d2["calls"] == 2 and d2["est_usd"] == d["est_usd"]


def test_ingest_session_summary(env, capsys):
    main(["ingest"])
    capsys.readouterr()
    from hx import ledger
    con = ledger.connect()
    row = con.execute("SELECT title, calls, tasks, tool_uses FROM session_summary").fetchone()
    assert row == ("Harness work", 2, "sw-lbm.3", 1)
    assert con.execute("SELECT provider FROM call WHERE call_id='msg_B'").fetchone()[0] == "anthropic"
    con.close()
