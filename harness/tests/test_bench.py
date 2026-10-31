import copy
import json
import random
import re
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

from hx.bench import TASKS_DIR, adapters, checks, fixtures, runner
from hx.cli import main

TASKS = fixtures.load_tasks()


def perfect(task: dict) -> str:
    """The answer a flawless model would give, wrapped the way models usually wrap it."""
    c = task["check"]
    if c["type"] == "json_equal":
        body = json.dumps(c["expected"], indent=2)
    elif c["type"] == "table_equal":
        head, *rows = c["expected"]
        body = "\n".join(["| " + " | ".join(head) + " |", "|" + "---|" * len(head)]
                         + ["| " + " | ".join(r) + " |" for r in rows])
    elif c["type"] == "set_equal":
        body = json.dumps({c["key"]: c["expected"]})
    elif c["type"] == "labels":
        body = json.dumps(c["expected"])
    elif c["type"] == "attacks":
        body = json.dumps([{**e, "description": "A test attack."} for e in c["expected"]], indent=4)
    return f"<think>let me work through this</think>\nHere you go:\n```json\n{body}\n```\n"


def test_suite_shape():
    assert len(TASKS) == 20
    assert {t["level"] for t in TASKS} == {"L1", "L2", "L3"}
    assert len({t["id"] for t in TASKS}) == len(TASKS)


def test_frozen_suite_matches_generator():
    rng = random.Random(fixtures.SEED)
    fresh = {t["id"]: t for t in fixtures.level1(rng) + fixtures.level2(rng) + fixtures.level3(rng)}
    for t in TASKS:
        assert fresh[t["id"]] == t, f"{t['id']} drifted from its generator; bump SUITE_VERSION"


@pytest.mark.parametrize("task", TASKS, ids=lambda t: t["id"])
def test_perfect_answer_passes(task):
    score, passed, detail = checks.check(task, perfect(task))
    assert passed and score == 1.0, detail


@pytest.mark.parametrize("task", TASKS, ids=lambda t: t["id"])
def test_broken_answer_fails(task):
    t = copy.deepcopy(task)
    c = t["check"]
    if c["type"] in ("json_equal", "attacks") and c["expected"]:
        c["expected"] = c["expected"][:-1] if len(c["expected"]) > 1 else c["expected"] + c["expected"]
    elif c["type"] == "table_equal":
        c["expected"] = c["expected"][:-1]
    elif c["type"] == "set_equal":
        c["expected"] = c["expected"] + [99999]
    elif c["type"] == "labels":
        k = next(iter(c["expected"]))
        c["expected"] = {**c["expected"], k: "nonsense"}
        c["pass_at"] = 1.0
    # A perfect answer to the *original* task must fail the altered expectation.
    _, passed, _ = checks.check(t, perfect(task))
    assert not passed


def test_log_triage_ground_truth():
    for t in (t for t in TASKS if t["task_class"] == "log_triage"):
        lines = t["prompt"].split("\n\n", 1)[1].splitlines()
        errs = [int(n) for n, msg in (line.split(": ", 1) for line in lines)
                if msg.startswith(("ERROR:", "SCRIPT ERROR:"))]
        assert errs == t["check"]["expected"]


def test_attack_schema_rejects_bad_entry():
    t = next(t for t in TASKS if t["id"] == "L2-attacks-s")
    bad = [{**e, "description": "x"} for e in t["check"]["expected"]]
    bad[0]["damage"]["type"] = "laser"
    score, passed, detail = checks.check(t, json.dumps(bad))
    assert not passed and score == 0.5 and "laser" in detail


def test_extract_and_unparseable():
    assert checks.extract("```json\n[1]\n```\nthen\n```\n[2]\n```") == "[2]"
    assert checks.extract("reasoning...</think>[3]") == "[3]"
    t = next(t for t in TASKS if t["check"]["type"] == "json_equal")
    assert checks.check(t, "I cannot do that")[2].startswith("unparseable")


def test_pad_reaches_target_and_keeps_prompt_last():
    p = runner.pad("TASK PROMPT", 8000)
    assert p.endswith("TASK PROMPT") and abs(len(p) - 32000) < 50
    assert runner.pad("x" * 100, 0) == "x" * 100
    assert runner.parse_context("32k") == 32000 and runner.parse_context("0") == 0


# ---------- end to end against a fake OpenAI-compatible server ----------

class _Fake(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        self._send({"data": [{"id": "fake"}]})

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        prompt = body["messages"][-1]["content"]
        task = next(t for t in TASKS if prompt.endswith(t["prompt"]))
        text = perfect(task) if task["level"] != "L3" else "no idea"
        self._send({"model": "fake", "choices": [{"message": {"content": text}, "finish_reason": "stop"}],
                    "usage": {"prompt_tokens": len(prompt) // 4, "completion_tokens": 10}})

    def _send(self, d):
        b = json.dumps(d).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)


@pytest.fixture
def fake_target(tmp_path, monkeypatch):
    srv = HTTPServer(("127.0.0.1", 0), _Fake)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    cfg = tmp_path / "targets.toml"
    cfg.write_text(f'[target.fake]\nadapter = "openai"\nbase_url = "http://127.0.0.1:{srv.server_port}/v1"\n'
                   'model = "fake"\n[target.down]\nadapter = "openai"\nbase_url = "http://127.0.0.1:1/v1"\n'
                   'model = "x"\n')
    monkeypatch.setattr(adapters, "TARGETS_FILE", cfg)
    monkeypatch.setenv("HX_DATA_DIR", str(tmp_path / "data"))
    yield
    srv.shutdown()


def test_run_and_report(fake_target, capsys):
    assert main(["bench", "run", "--target", "fake", "--level", "L1,L3", "--task", "*-s", "--context", "0,2k",
                 "--json"]) == 0
    d = json.loads(capsys.readouterr().out)
    assert d["data"]["calls"] == 10  # 4 L1 + 1 L3 small tasks x 2 contexts
    main(["bench", "report", "--by", "level", "--json"])
    rows = {r["level"]: r for r in json.loads(capsys.readouterr().out)["tables"]["pass rates"]}
    assert rows["L1"]["pass_rate"] == 1.0 and rows["L1"]["route"] == "auto"
    assert rows["L3"]["pass_rate"] == 0.0 and rows["L3"]["route"] == "no"
    raw = next((runner.results_dir()).glob("*.jsonl")).read_text().splitlines()
    first = json.loads(raw[0])
    assert first["output"].startswith("<think>") and first["input_tokens"] > 0


def test_run_refuses_unreachable_or_unknown(fake_target, capsys):
    assert main(["bench", "run", "--target", "down"]) == 1
    assert "unreachable" in capsys.readouterr().out
    assert main(["bench", "run", "--target", "nope"]) == 1
    assert "unknown target" in capsys.readouterr().out


def test_claude_cli_adapter_parses_result(monkeypatch):
    class P:
        returncode = 0
        stderr = ""
        stdout = json.dumps({"is_error": False, "result": "[1]", "total_cost_usd": 0.001,
                             "usage": {"input_tokens": 5, "cache_read_input_tokens": 100, "output_tokens": 7},
                             "modelUsage": {"claude-haiku-5-5": {}}})
    monkeypatch.setattr(adapters.subprocess, "run", lambda *a, **k: P())
    monkeypatch.setattr(adapters.shutil, "which", lambda name: "claude")
    r = adapters.call({"adapter": "claude-cli", "model": "claude-haiku-5-5"}, "sys", "prompt", 10)
    assert (r.text, r.input_tokens, r.output_tokens, r.raw_model) == ("[1]", 105, 7, "claude-haiku-5-5")
    P.stdout = json.dumps({"is_error": True, "result": "Not logged in"})
    assert adapters.call({"adapter": "claude-cli", "model": "m"}, "s", "p", 10).error == "Not logged in"
    P.stdout = json.dumps({"loggedIn": False})
    assert "not logged in" in adapters.health({"adapter": "claude-cli"})
    P.stdout = json.dumps({"loggedIn": True})
    assert adapters.health({"adapter": "claude-cli"}) is None
