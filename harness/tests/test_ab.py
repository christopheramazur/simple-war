import json
import os
import shutil
import subprocess
from datetime import datetime
from pathlib import Path

from hx import ledger
from hx.commands import ab
from hx.commands.ingest import _import_ab_arms

HOOK = Path(__file__).resolve().parents[1] / "bin" / "rtk-hook"
# Git Bash, not WSL's bash.exe in System32, which Windows PATH lookup can return first.
BASH = next((b for b in ("C:/Program Files/Git/bin/bash.exe",) if Path(b).exists()), None) or shutil.which("bash")


def arm(sessions, calls, tpc, err):
    return {"sessions": sessions, "bash_calls": calls, "tokens_per_call": tpc, "error_rate": err}


def test_verdicts():
    assert ab.verdict({1: arm(3, 50, 100, 0.0)})[0] == "collecting"
    assert ab.verdict({1: arm(12, 300, 70, 0.05), 0: arm(11, 280, 100, 0.04)})[0] == "keep"
    assert ab.verdict({1: arm(12, 300, 90, 0.05), 0: arm(11, 280, 100, 0.04)})[0] == "drop"   # only 10% saved
    assert ab.verdict({1: arm(12, 300, 60, 0.09), 0: arm(11, 280, 100, 0.04)})[0] == "drop"   # more retries


def test_hook_logs_arm_once_and_forces(tmp_path):
    env = {**os.environ, "HX_DATA_DIR": str(tmp_path), "HX_RTK": "off"}
    payload = json.dumps({"session_id": "sX", "tool_name": "Bash", "tool_input": {"command": "git status"}})
    for _ in range(2):
        p = subprocess.run([BASH, str(HOOK)], input=payload, capture_output=True, text=True, env=env)
        assert p.returncode == 0 and p.stdout == ""  # off arm: command untouched
    rows = [json.loads(x) for x in (tmp_path / "raw" / "rtk" / "arms.jsonl").read_text().splitlines()]
    assert rows == [{"ts": rows[0]["ts"], "session_id": "sX", "rtk": 0, "forced": True}]


def test_arms_ingested_and_compared(tmp_path, monkeypatch):
    monkeypatch.setenv("HX_DATA_DIR", str(tmp_path))
    raw = tmp_path / "raw" / "rtk"
    raw.mkdir(parents=True)
    raw.joinpath("arms.jsonl").write_text(
        '{"ts":"2026-11-01T01:00:00Z","session_id":"a","rtk":1,"forced":false}\n'
        '{"ts":"2026-11-01T01:00:00Z","session_id":"b","rtk":0,"forced":false}\n'
        '{"ts":"2026-11-01T01:00:00Z","session_id":"c","rtk":1,"forced":true}\n')
    con = ledger.connect(tmp_path / "l.duckdb")
    assert _import_ab_arms(con) == 3
    t = datetime(2026, 11, 1, 1)
    for sid, chars in (("a", 400), ("b", 1000), ("c", 4)):
        ledger.upsert(con, "tool_use", [{"tool_use_id": f"u{sid}", "call_id": None, "session_id": sid, "agent_id": None,
                                         "ts": t, "tool": "Bash", "input_chars": 10, "command": "git status"}])
        ledger.upsert(con, "tool_result", [{"tool_use_id": f"u{sid}", "session_id": sid, "ts": t,
                                            "result_chars": chars, "is_error": False, "denied": None}])
    a = ab.arms(con, "rtk")
    assert a[1]["tokens_per_call"] == 100 and a[0]["tokens_per_call"] == 250  # forced session c excluded
