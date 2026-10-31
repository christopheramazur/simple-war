import json
from datetime import datetime, timedelta

import duckdb
import pytest

from hx import ledger, report, report_html
from hx.cli import main

T0 = datetime(2026, 10, 31, 1, 0, 0)


def call(cid, minutes, usd_out=1000, agent=None, model="claude-opus-5-5"):
    return {"call_id": cid, "session_id": "s1", "agent_id": agent, "client": "claude-code", "provider": "anthropic",
            "model": model, "ts": T0 + timedelta(minutes=minutes), "input_tokens": 10, "output_tokens": usd_out,
            "cache_read_tokens": 900, "cache_write_5m_tokens": 0, "cache_write_1h_tokens": 90,
            "thinking_tokens": 0, "stop_reason": "end_turn", "est_usd": usd_out / 1000, "source": "t"}


@pytest.fixture
def con(tmp_path):
    c = ledger.connect(tmp_path / "l.duckdb")
    ledger.upsert(c, "session", [{"session_id": "s1", "client": "claude-code", "project": "p", "cwd": None,
                                  "git_branch": None, "title": "T", "entrypoint": None, "client_version": None}])
    ledger.upsert(c, "call", [call("a", 0), call("b", 10), call("c", 20, agent="sub"), call("d", 30),
                              call("e", 40, model="claude-haiku-5-5")])
    ledger.upsert(c, "session_task", [
        {"session_id": "s1", "task_id": "sw-1", "ts": T0 + timedelta(minutes=5), "source": "claim"},
        {"session_id": "s1", "task_id": "sw-1", "ts": T0 + timedelta(minutes=25), "source": "close"},
        {"session_id": "s1", "task_id": "sw-2", "ts": T0 + timedelta(minutes=35), "source": "claim"},
    ])
    ledger.upsert(c, "tool_use", [
        {"tool_use_id": "t1", "call_id": "b", "session_id": "s1", "agent_id": None, "ts": T0 + timedelta(minutes=10),
         "tool": "Bash", "input_chars": 10, "command": "cd /x && git status --short | head"},
        {"tool_use_id": "t2", "call_id": "d", "session_id": "s1", "agent_id": None, "ts": T0 + timedelta(minutes=30),
         "tool": "Bash", "input_chars": 10, "command": "echo hi; git status"},
    ])
    ledger.upsert(c, "tool_result", [
        {"tool_use_id": "t1", "session_id": "s1", "ts": T0 + timedelta(minutes=11), "result_chars": 400,
         "is_error": False, "denied": None},
        {"tool_use_id": "t2", "session_id": "s1", "ts": T0 + timedelta(minutes=31), "result_chars": 40,
         "is_error": True, "denied": None},
    ])
    # Prompt at 0, activity to 11; next prompt at 15 (4 min wait); activity to 31; prompt at 120 (89 min gap).
    ledger.upsert(c, "event", [
        {"event_id": f"prompt:{m}", "session_id": "s1", "agent_id": None, "ts": T0 + timedelta(minutes=m),
         "kind": "prompt", "value": 5, "detail": None} for m in (0, 15, 120)
    ] + [{"event_id": "interrupt:1", "session_id": "s1", "agent_id": None, "ts": T0, "kind": "interrupt",
          "value": None, "detail": None}])
    yield c
    c.close()


def test_task_attribution_claim_close_and_subagents(con):
    d = report.build(con, datetime(2000, 1, 1), timedelta(hours=10))
    tasks = {r["task"]: r for r in d["by_task"]}
    # a: before claim; b,c(subagent): sw-1; d: after close; e: sw-2.
    assert tasks["sw-1"]["calls"] == 2 and tasks["sw-1"]["closed"] is True
    assert tasks["(none)"]["calls"] == 2
    assert tasks["sw-2"]["calls"] == 1 and tasks["sw-2"]["closed"] is False
    t = d["totals"]
    assert t["tasks_closed"] == 1 and t["usd_per_closed_task"] == pytest.approx(2.0)
    assert t["cache_hit"] == pytest.approx(900 / 1000)


def test_tools_commands_friction(con):
    d = report.build(con, datetime(2000, 1, 1))
    assert d["tools"][0] == {"tool": "Bash", "uses": 2, "errors": 1, "denied": 0,
                             "output_tokens_est": 110, "avg_tokens": 55.0}
    assert d["commands"] == [{"command": "git status", "uses": 2, "output_tokens_est": 110}]
    assert d["friction"]["tool_errors"] == 1 and d["friction"]["interrupts"] == 1


def test_time_split(con):
    tm = report.build(con, datetime(2000, 1, 1))["time"]
    # Work: 0->11 (11 min) + 15->40 (25: calls d at 30, e at 40, result at 31) + 0 for last prompt.
    # Wait: 4 min + 30 min (capped); away: 80 - 30 = 50 min... gap 40->120 = 80 min.
    assert tm["turns"] == 3
    assert tm["agent_work_h"] == round(36 / 60, 2)
    assert tm["human_wait_h"] == round(34 / 60, 2)
    assert tm["away_h"] == round(50 / 60, 2)


def test_by_day_uses_local_offset(con):
    rows = report.build(con, datetime(2000, 1, 1), timedelta(hours=-2))["by_day"]
    assert {str(r["day"]) for r in rows} == {"2026-10-30"}


@pytest.mark.parametrize("cmd,key", [
    ("cd x && git status --short | head", "git status"),
    ("time uv run --project h pytest", "uv run"),
    ("(cd a && bd update sw-1 --claim)", "bd update"),
    ("FOO=1 python -c 'x'", "python"),
    ("ls -la /c/x", "ls"),
    ("/usr/bin/grep -n foo", "grep"),
])
def test_command_key(cmd, key):
    assert report.command_key(cmd) == key


def test_parse_since():
    now = datetime(2026, 10, 31, 12)
    assert report.parse_since("7d", now) == datetime(2026, 10, 24, 12)
    assert report.parse_since("24h", now) == datetime(2026, 10, 30, 12)
    assert report.parse_since("all", now).year == 1970


def test_html_renders_self_contained(con):
    d = report.build(con, datetime(2000, 1, 1))
    page = report_html.render(d, "all", datetime(2026, 10, 31))
    assert page.startswith("<!doctype html>") and "<title>Harness Report</title>" in page
    assert "claude-haiku-5-5" in page and "data-tip=" in page and "Table view" in page
    assert "http://" not in page and "https://" not in page  # no external assets


def test_report_cli(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("HX_DATA_DIR", str(tmp_path))
    assert main(["report"]) == 0
    assert "run hx ingest" in capsys.readouterr().out
    c = ledger.connect()
    ledger.upsert(c, "call", [call("a", 0)])
    c.close()
    main(["report", "--since", "all", "--html", "--json"])
    d = json.loads(capsys.readouterr().out)
    assert d["data"]["totals"]["calls"] == 1 and "by_task" in d["tables"]
    assert (tmp_path / "reports" / "report.html").exists()
