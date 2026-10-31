import json
import re
import subprocess
import sys
import time

import pytest

from hx import quota, statusline
from hx.cli import main

NOW = 1_793_450_000.0  # fixed epoch
RESET_5H = NOW + 2 * 3600
RESET_7D = NOW + 4 * 86400


def inp(five=40.0, seven=10.0, **extra):
    return {"session_id": "s1", "model": {"display_name": "Opus 5.5"},
            "rate_limits": {"five_hour": {"used_percentage": five, "resets_at": RESET_5H},
                            "seven_day": {"used_percentage": seven, "resets_at": RESET_7D}},
            "context_window": {"used_percentage": 34.4}, "cost": {"total_cost_usd": 1.2}, **extra}


def plain(s: str) -> str:
    return re.sub(r"\033\[\d+m", "", s)


@pytest.fixture(autouse=True)
def data(tmp_path, monkeypatch):
    monkeypatch.setenv("HX_DATA_DIR", str(tmp_path))
    return tmp_path


def test_record_throttles_unchanged():
    snaps = quota.from_statusline(inp(), NOW)
    assert len(quota.record(snaps, [])) == 2
    hist = quota.read_tail(quota.log_path())
    assert quota.record(quota.from_statusline(inp(), NOW + 60), hist) == []  # same values, too soon
    assert len(quota.record(quota.from_statusline(inp(), NOW + 301), hist)) == 2  # heartbeat
    assert len(quota.record(quota.from_statusline(inp(five=41), NOW + 61), hist)) == 1  # changed


def test_read_tail_skips_partial_first_line(data):
    p = quota.log_path()
    p.parent.mkdir(parents=True)
    line = json.dumps(quota.Snapshot(NOW, "five_hour", 1.0, RESET_5H).__dict__) + "\n"
    p.write_text(line * 50)
    assert len(quota.read_tail(p, max_bytes=len(line) * 3 + 5)) == 3


def test_projection():
    first = quota.Snapshot(NOW, "five_hour", 20.0, RESET_5H)
    cur = quota.Snapshot(NOW + 3600, "five_hour", 70.0, RESET_5H)  # 50%/h -> full in 36 min, reset in 1h
    p = quota.project(cur, [first, cur])
    assert p.rate_per_h == 50.0 and p.will_hit_limit and p.full_at == pytest.approx(NOW + 3600 + 2160, abs=1)
    slow = quota.Snapshot(NOW + 3600, "five_hour", 25.0, RESET_5H)
    assert not quota.project(slow, [first, slow]).will_hit_limit
    other_window = quota.Snapshot(NOW, "five_hour", 5.0, RESET_5H - 18000)  # previous window ignored
    assert quota.project(cur, [other_window, cur]).full_at is None


def test_render_full_line(data):
    (data / "cache").mkdir()
    (data / "cache" / "summary.json").write_text(json.dumps(
        {"generated_at": NOW, "today_usd": 8.45, "usd_per_closed_task": 1.12}))
    out = plain(statusline.render(inp(), NOW))
    assert out.startswith("Opus 5.5 · 5h 40% ↺")
    assert "7d 10% ↺" in out and "ctx 34%" in out and "sess $1.20" in out
    assert "today $8.45 · $1.12/task" in out and "?" not in out


def test_render_warns_on_projected_limit_and_stale_cache(data):
    statusline.render(inp(five=20), NOW)
    (data / "cache").mkdir()
    (data / "cache" / "summary.json").write_text(json.dumps({"generated_at": NOW - 7 * 3600, "today_usd": 1}))
    out = plain(statusline.render(inp(five=70), NOW + 3600))
    assert "⚠ full ~" in out and "today $1.00?" in out


def test_render_without_rate_limits_or_cache():
    out = plain(statusline.render({"model": {"display_name": "Sonnet"}}, NOW))
    assert out == "Sonnet"
    assert not quota.log_path().exists()


def test_main_never_crashes_on_garbage():
    r = subprocess.run([sys.executable, "-m", "hx.statusline"], input=b"{not json", capture_output=True)
    assert r.returncode == 0 and b"statusline error" in r.stdout


def test_ingest_loads_quota_and_writes_summary(data, monkeypatch, capsys):
    monkeypatch.setenv("HX_CLAUDE_PROJECTS", str(data / "none"))
    t = time.time()
    statusline.render(inp(five=20), t - 3600)
    statusline.render(inp(five=60), t)
    assert main(["ingest", "--json"]) == 0
    d = json.loads(capsys.readouterr().out)["data"]
    assert d["quota_snapshots"] == 4
    summ = json.loads((data / "cache" / "summary.json").read_text())
    assert summ["today_usd"] == 0 and summ["generated_at"] >= t
    main(["report", "--since", "all", "--json"])
    q = {r["window"]: r for r in json.loads(capsys.readouterr().out)["tables"]["quota"]}
    assert q["five_hour"]["used_pct"] == 60.0 and q["five_hour"]["burn_pct_per_h"] == pytest.approx(40, abs=0.5)
