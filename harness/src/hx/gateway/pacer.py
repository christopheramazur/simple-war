"""Pacing of call starts for providers with an adaptive fair-share limit (Nous, 2026-11-20), with
priority lanes by caller (sw-0zi.2).

Four agents calling at once got ~90% 429s, so calls wait here instead of bouncing: the gap between
call starts grows x1.6 on each 429 and shrinks x0.93 on each success (AIMD), between `lo` and `hi`.

Under throttling only ~40 calls an hour start, and on 2026-11-21 first-come first-served gave workers 8%
of them. So a free start goes to the waiting call in the best lane: the user's own tools, then workers,
the orchestrator, deep research, the other support roles, the auditor. A waiting call moves up one lane
every `age_step` seconds, so even the lowest lane starts within about 5 * age_step.

Imported by litellm_hooks (inside the LiteLLM process); kept free of LiteLLM so it can be tested alone.
"""

from __future__ import annotations

import asyncio
import contextlib
import itertools
import time

# Lower is served first.
LANES = {"user": 0, "worker": 1, "postmortem": 1, "orchestrator": 2, "research": 3, "support": 4, "auditor": 5}


def lane(caller: str) -> int:
    """The lane of an x-hx-caller value: `swarm-<role>` for swarm turns, anything else is the user's."""
    if not caller.startswith("swarm-"):
        return LANES["user"]
    role = caller[len("swarm-"):]
    for prefix in ("worker", "postmortem", "orchestrator", "auditor"):
        if role == prefix or role.startswith(prefix + "-"):
            return LANES[prefix]
    if role.startswith("research-"):  # deep research jobs (not the researcher roles)
        return LANES["research"]
    return LANES["support"]  # designers, researchers, retro, anything new


class PriorityPacer:
    def __init__(self, gap: float = 4.0, lo: float = 2.0, hi: float = 90.0, age_step: float = 180.0, clock=time.monotonic):
        self.gap, self.lo, self.hi, self.age_step = gap, lo, hi, age_step
        self.clock = clock
        self.next_at = 0.0
        self.last_start = 0.0
        self.waiters: list[list] = []  # [lane, enqueued_at, seq]
        self._seq = itertools.count()
        self.cond = asyncio.Condition()
        self.started: dict[int, int] = {}  # lane -> call starts, for status and tests

    def _rank(self, w: list, now: float) -> tuple:
        return (w[0] - int((now - w[1]) // self.age_step), w[1], w[2])

    async def wait(self, caller: str = "") -> None:
        w = [lane(caller), self.clock(), next(self._seq)]
        async with self.cond:
            self.waiters.append(w)
            try:
                while True:
                    now = self.clock()
                    best = min(self.waiters, key=lambda x: self._rank(x, now))
                    if best is w and now >= self.next_at:
                        if self.last_start and now - self.last_start > 2 * self.gap:
                            self.gap = max(self.lo, self.gap * 0.8)  # quiet for a while: probe faster again
                        self.last_start = now
                        self.next_at = now + self.gap
                        self.started[w[0]] = self.started.get(w[0], 0) + 1
                        return
                    with contextlib.suppress(asyncio.TimeoutError):
                        await asyncio.wait_for(self.cond.wait(), timeout=max(0.01, min(5.0, self.next_at - now)))
            finally:
                self.waiters.remove(w)
                self.cond.notify_all()

    def ok(self) -> None:
        self.gap = max(self.lo, self.gap * 0.93)

    def limited(self) -> None:
        self.gap = min(self.hi, self.gap * 1.6)
        self.next_at = max(self.next_at, self.clock() + self.gap)
