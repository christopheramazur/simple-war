"""The swarm supervisor picks up swarm.toml edits while it runs (sw-0zi.1)."""

from __future__ import annotations

import json
import os
import threading
import time

import pytest

from hx import swarm

TOML = """
[run]
end_at = "2026-11-24T13:00:00+00:00"
core_slots = {core}
support_slots = 1

[workers]
max_parallel = {workers}

[audit]
every_s = {audit}
turn_timeout_s = 1800
"""


@pytest.fixture
def sv(tmp_path, monkeypatch):
    monkeypatch.setattr(swarm, "SWARM", tmp_path / "swarm")
    monkeypatch.setattr(swarm, "STATE", tmp_path / "state")
    (tmp_path / "swarm").mkdir()
    write(tmp_path, core=2, workers=1, audit=1800, mtime=1000)
    return swarm.Supervisor()


def write(tmp_path, *, core=2, workers=1, audit=1800, mtime, text=None):
    f = tmp_path / "swarm" / "swarm.toml"
    f.write_text(text if text is not None else TOML.format(core=core, workers=workers, audit=audit), encoding="utf-8")
    os.utime(f, (mtime, mtime))


def events(tmp_path):
    f = tmp_path / "state" / "events.jsonl"
    return [json.loads(line) for line in f.read_text(encoding="utf-8").splitlines()] if f.exists() else []


def test_unchanged_file_is_not_reloaded(sv, tmp_path):
    assert sv.maybe_reload() is None
    assert events(tmp_path) == []


def test_edit_applies_and_logs_changed_keys(sv, tmp_path):
    write(tmp_path, core=3, audit=2700, mtime=2000)
    changed = sv.maybe_reload()
    assert changed == ["audit.every_s", "run.core_slots"]
    assert sv.c["audit"]["every_s"] == 2700
    assert sv.pools["core"].size == 3
    assert events(tmp_path)[-1] == {**events(tmp_path)[-1], "kind": "config_reloaded", "changed": changed}


def test_touch_without_change_logs_nothing(sv, tmp_path):
    write(tmp_path, mtime=3000)
    assert sv.maybe_reload() is None
    assert events(tmp_path) == []


@pytest.mark.parametrize("text", ["[run\nbroken", "[run]\ncore_slots = 2\n"])
def test_bad_file_keeps_running_config(sv, tmp_path, text):
    write(tmp_path, mtime=4000, text=text)
    assert sv.maybe_reload() is None
    assert sv.c["run"]["core_slots"] == 2
    assert [e["kind"] for e in events(tmp_path)] == ["config_error"]
    assert sv.maybe_reload() is None  # logged once per edit, not every loop
    assert len(events(tmp_path)) == 1


def test_more_workers_start_more_threads(sv, tmp_path, monkeypatch):
    seen = []
    monkeypatch.setattr(swarm.Supervisor, "worker_loop", lambda self, n: seen.append(n))
    sv.start_workers()
    write(tmp_path, workers=3, mtime=5000)
    sv.maybe_reload()
    deadline = time.time() + 5
    while len(seen) < 3 and time.time() < deadline:
        time.sleep(0.01)
    assert sorted(seen) == [0, 1, 2]
    assert sv.workers_started == 3


def test_shrinking_a_pool_never_interrupts_a_running_turn():
    slots = swarm.Slots(2)
    slots.__enter__()
    slots.__enter__()
    slots.resize(1)
    got = threading.Event()

    def take():
        with slots:
            got.set()

    t = threading.Thread(target=take, daemon=True)
    t.start()
    slots.__exit__(None, None, None)  # one of two running turns ends: still at the new limit of 1
    assert not got.wait(0.2)
    slots.__exit__(None, None, None)  # the other ends: a slot is free
    assert got.wait(2)
    t.join(2)


def test_cfg_diff_handles_nested_added_and_removed_keys():
    assert swarm.cfg_diff({"a": {"x": 1, "y": 2}, "b": 1}, {"a": {"x": 1, "z": 3}, "c": 1}) == ["a.y", "a.z", "b", "c"]
