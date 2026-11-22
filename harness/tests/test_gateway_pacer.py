"""Gateway pacing with priority lanes, and the supervisor pausing support turns while throttled (sw-0zi.2)."""

from __future__ import annotations

import asyncio
import json
import time

import pytest

from hx import swarm
from hx.gateway.pacer import LANES, PriorityPacer, lane


@pytest.mark.parametrize("caller, expected", [
    ("", "user"), ("-", "user"), ("bench", "user"),
    ("swarm-worker-sw-ll4.27.3", "worker"), ("swarm-postmortem", "postmortem"),
    ("swarm-orchestrator", "orchestrator"), ("swarm-research-telegraphing-enemy", "research"),
    ("swarm-lead-designer", "support"), ("swarm-games-researcher", "support"), ("swarm-retro", "support"),
    ("swarm-auditor", "auditor"),
])
def test_lanes(caller, expected):
    assert lane(caller) == LANES[expected]


def test_a_free_start_goes_to_the_best_lane():
    async def main():
        p = PriorityPacer(gap=0.03, lo=0.03)
        p.next_at = p.clock() + 0.2  # every caller arrives while the next start is still blocked
        order = []

        async def call(caller):
            await p.wait(caller)
            order.append(caller)
        callers = ["swarm-auditor", "swarm-lead-designer", "swarm-orchestrator", "swarm-worker-sw-a", "-"]
        tasks = [asyncio.create_task(call(c)) for c in callers]
        await asyncio.gather(*tasks)
        return order
    assert asyncio.run(main()) == ["-", "swarm-worker-sw-a", "swarm-orchestrator", "swarm-lead-designer", "swarm-auditor"]


def test_a_low_lane_call_is_not_starved():
    async def main():
        p = PriorityPacer(gap=0.02, lo=0.02, age_step=0.1)
        stop = asyncio.Event()
        got = {}

        async def flood():  # workers keep arriving faster than starts free up
            while not stop.is_set():
                asyncio.create_task(p.wait("swarm-worker-sw-a"))
                await asyncio.sleep(0.01)

        async def auditor():
            t0 = time.monotonic()
            await p.wait("swarm-auditor")
            got["waited"] = time.monotonic() - t0
            stop.set()
        f = asyncio.create_task(flood())
        await asyncio.wait_for(auditor(), timeout=5)
        await f
        return got["waited"]
    # lane 5 reaches the workers' lane 1 after 4 age steps (0.4 s); it is then the oldest waiter
    assert asyncio.run(main()) < 1.0


def test_workers_get_most_starts_under_contention():
    """The 2026-11-21 evening in miniature: one worker, the orchestrator, three support roles and the
    auditor each call again as soon as their call starts. First come first served gave workers 8%."""
    async def main():
        p = PriorityPacer(gap=0.01, lo=0.01, hi=0.01, age_step=0.25)
        done = asyncio.Event()

        async def agent(caller):
            while not done.is_set():
                await p.wait(caller)
                await asyncio.sleep(0)
        callers = ["swarm-worker-sw-a", "swarm-orchestrator", "swarm-lead-designer", "swarm-games-researcher",
                   "swarm-craft-researcher", "swarm-auditor"]
        tasks = [asyncio.create_task(agent(c)) for c in callers]
        await asyncio.sleep(0.8)
        done.set()
        await asyncio.wait_for(asyncio.gather(*tasks), timeout=5)
        return p.started
    started = asyncio.run(main())
    total = sum(started.values())
    assert total >= 30
    assert started.get(LANES["worker"], 0) / total > 0.5, started


def test_aimd_bounds_and_quiet_probe():
    t = [100.0]
    p = PriorityPacer(gap=4.0, lo=2.0, hi=90.0, clock=lambda: t[0])
    for _ in range(20):
        p.limited()
    assert p.gap == 90.0
    for _ in range(200):
        p.ok()
    assert p.gap == 2.0
    p.gap = 60.0
    p.last_start = 100.0
    t[0] = 400.0  # quiet for 5 minutes, longer than two gaps
    p.next_at = 0.0
    asyncio.run(p.wait("swarm-worker-x"))
    assert p.gap == pytest.approx(48.0)


# ---------------------------------------------------------------- supervisor: support turns pause while throttled

@pytest.fixture
def sv(tmp_path, monkeypatch):
    monkeypatch.setattr(swarm, "STATE", tmp_path / "state")
    s = swarm.Supervisor.__new__(swarm.Supervisor)
    s.c = {"run": {"throttle_share_on": 0.4, "throttle_share_off": 0.25, "throttle_min_ok_per_h": 30}}
    s.rows = []
    monkeypatch.setattr(swarm, "_gateway_rows", lambda since: s.rows)
    return s


def rows(ok, limited, caller="swarm-worker-sw-a"):
    return ([{"caller": caller, "status": "success"}] * ok
            + [{"caller": caller, "status": "failure", "error": "litellm.RateLimitError: ..."}] * limited)


def check(s):
    s._throttle_checked = 0.0  # skip the once-a-minute cache
    return s.support_paused()


def test_throttle_switches_with_hysteresis(sv, tmp_path):
    sv.rows = rows(80, 10)
    assert check(sv) is False
    sv.rows = rows(40, 40)  # 50% rate-limited
    assert check(sv) is True
    sv.rows = rows(60, 25)  # 29%: above the off threshold, still paused
    assert check(sv) is True
    sv.rows = rows(80, 10)  # 11% and enough successes
    assert check(sv) is False
    kinds = [json.loads(line)["kind"] for line in (tmp_path / "state" / "events.jsonl").read_text().splitlines()]
    assert kinds == ["throttle_on", "throttle_off"]


def test_too_few_successes_pause_too(sv):
    sv.rows = rows(15, 5)  # 25% limited, but only 15 successful calls in the hour
    assert check(sv) is True


def test_little_traffic_or_non_swarm_calls_never_pause(sv):
    sv.rows = rows(2, 6)
    assert check(sv) is False
    sv.rows = rows(5, 60, caller="-")
    assert check(sv) is False


def test_result_is_cached_for_a_minute(sv):
    sv.rows = rows(10, 40)
    assert check(sv) is True
    sv.rows = rows(90, 0)
    assert sv.support_paused() is True  # cached
    assert check(sv) is False
