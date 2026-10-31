from datetime import datetime, timedelta, timezone

import duckdb
import pytest

from hx import mining
from hx.delegate import Outcome


def test_shape_drops_nav_pipes_and_reads_wrappers():
    assert mining.shape("cd C:/x && uv run --project harness pytest -q 2>&1 | tail -3") == "uv run pytest"
    assert mining.shape("cd x; git add -A && git commit -m 'm' && git push") == "git add && git commit && git push"
    assert mining.shape("uvx --python 3.14 --with tzdata litellm --port 4000") == "uvx litellm"


def test_hx_verb_only_real_verbs():
    assert mining.hx_verb("harness/bin/hx bench run --target x") == "bench"
    assert mining.hx_verb('python -c "from hx import mining"') is None


@pytest.fixture
def con(tmp_path, monkeypatch):
    monkeypatch.setenv("HX_DATA_DIR", str(tmp_path))
    c = duckdb.connect()
    c.execute("CREATE TABLE tool_use (tool_use_id TEXT, session_id TEXT, command TEXT, input_chars BIGINT)")
    c.execute("CREATE TABLE tool_result (tool_use_id TEXT, result_chars BIGINT)")
    rows = []
    for s in range(4):
        for i in range(2):
            rows.append((f"{s}-{i}", f"s{s}", "git add -A && git commit -m x && git push", 40))
        rows.append((f"{s}-r", f"s{s}", "cat file.txt", 10))
        rows.append((f"{s}-h", f"s{s}", "harness/bin/hx status", 20))
    c.executemany("INSERT INTO tool_use VALUES (?, ?, ?, ?)", rows)
    c.executemany("INSERT INTO tool_result VALUES (?, ?)", [(r[0], 400) for r in rows])
    return c


def test_candidates_skip_primitives_and_hx(con):
    cands = mining.candidates(con, min_sessions=3, min_uses=5)
    assert [c["shape"] for c in cands] == ["git add && git commit && git push"]
    assert cands[0]["uses"] == 8 and cands[0]["sessions"] == 4 and cands[0]["tokens_per_use"] == 110


def test_run_files_once_and_throttles(con):
    made = []
    prop = Outcome(target="b", model="bonsai/nothink", text='{"verb": "hx ship", "purpose": "commit and push"}')
    create = lambda title, body: made.append(title) or f"sw-{len(made)}"  # noqa: E731
    t0 = datetime(2026, 11, 1, tzinfo=timezone.utc)
    out = mining.run(con, delegate_run=lambda *a: prop, create=create, now=t0)
    assert made == ["hx verb candidate: hx ship"] and out["filed"][0]["issue"] == "sw-1"
    assert mining.run(con, create=create, now=t0 + timedelta(hours=1))["skipped"]
    out = mining.run(con, delegate_run=lambda *a: prop, create=create, now=t0 + timedelta(hours=7))
    assert out["filed"] == [] and len(made) == 1  # already filed
    assert mining.load_state()["filed"]["git add && git commit && git push"]["baseline_tokens_per_use"] == 110


def test_verb_usage(con):
    assert mining.verb_usage(con) == [{"verb": "status", "uses": 4, "tokens_per_use": 100}]
