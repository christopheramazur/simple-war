"""LiteLLM proxy callbacks: budget/quota gate before each call, raw log after it.

Imported inside the LiteLLM process (PYTHONPATH includes harness/src). Fallback is NOT
done by LiteLLM: its pre-call hook only sees the first model of a chain, so per-provider
enforcement would be bypassed. Callers (hx delegate) retry the next model on a 429.
"""

from __future__ import annotations

import time
from datetime import datetime, timezone

from fastapi import HTTPException
from litellm.integrations.custom_logger import CustomLogger

from hx import providers
from hx.gateway import budget, config


SWARM_MODEL = "nous/qwen4-max"


class Pacer:
    """AIMD pacing of call starts for a provider with an adaptive fair-share limit (Nous, 2026-11-20):
    four agents calling at once got ~90% 429s, so calls wait here instead of bouncing.
    The gap between starts grows x1.6 on each 429 and shrinks x0.93 on each success."""

    def __init__(self, gap: float = 4.0, lo: float = 2.0, hi: float = 90.0):
        import asyncio
        self.gap, self.lo, self.hi = gap, lo, hi
        self.next_at = 0.0
        self.lock = asyncio.Lock()

    async def wait(self) -> None:
        import asyncio
        async with self.lock:
            delay = self.next_at - time.monotonic()
            if delay > 0:
                await asyncio.sleep(delay)
            self.next_at = time.monotonic() + self.gap

    def ok(self) -> None:
        self.gap = max(self.lo, self.gap * 0.93)

    def limited(self) -> None:
        self.gap = min(self.hi, self.gap * 1.6)
        self.next_at = max(self.next_at, time.monotonic() + self.gap)


PACED = {"nous"}


def _caller(data: dict) -> str:
    """x-hx-caller from the request headers, wherever this LiteLLM version puts them."""
    for src in ((data.get("metadata") or {}).get("headers"), (data.get("proxy_server_request") or {}).get("headers")):
        if isinstance(src, dict):
            for k, v in src.items():
                if k.lower() == "x-hx-caller":
                    return str(v)
    return ""


def _logged_caller(kwargs: dict, md: dict) -> str | None:
    """x-hx-caller for a finished call: LiteLLM versions keep request headers in different places."""
    lp = kwargs.get("litellm_params") or {}
    for d in (md, lp.get("metadata") or {}, kwargs.get("metadata") or {}):
        if isinstance(d, dict) and d.get("hx_caller"):
            return d["hx_caller"]
    for data in (lp, kwargs, {"metadata": md}):
        c = _caller(data if isinstance(data, dict) else {})
        if c:
            return c
    return None


class HxHooks(CustomLogger):
    def __init__(self):
        super().__init__()
        self.roster = providers.load()
        self.aliases = config.alias_map(self.roster)  # "groq/llama70b" -> "groq"
        self.tracker = budget.Tracker(self.roster)
        self.tracker.seed(budget.read_log())
        self.pacers = {p: Pacer() for p in PACED}

    def _provider(self, model: str | None) -> str | None:
        return self.aliases.get(model or "")

    async def async_pre_call_hook(self, user_api_key_dict, cache, data: dict, call_type):
        model = data.get("model")
        pid = self._provider(model)
        caller = _caller(data)
        if caller.startswith("swarm") and model != SWARM_MODEL:  # the Qwen swarm fails closed (harness/swarm)
            budget.append_log({"ts": _now(), "provider": pid, "model_group": model, "status": "refused",
                               "error": f"swarm caller {caller} may only use {SWARM_MODEL}", "caller": caller})
            raise HTTPException(status_code=403, detail=f"swarm callers may only use {SWARM_MODEL}")
        if caller and isinstance(data.get("metadata"), dict):
            data["metadata"]["hx_caller"] = caller  # survives into the success/failure log row
        if pid is None:
            raise HTTPException(status_code=404, detail=f"unknown model {model!r}; see hx gateway status")
        d = self.tracker.check(pid, time.time())
        if not d.allowed:
            budget.append_log({"ts": _now(), "provider": pid, "model_group": model, "status": "refused",
                               "error": d.reason})
            raise HTTPException(status_code=429, detail=d.reason)
        if pid in self.pacers:
            await self.pacers[pid].wait()
        return data

    def _row(self, kwargs, status: str) -> dict:
        s = kwargs.get("standard_logging_object") or {}
        group = s.get("model_group") or kwargs.get("model")
        pid = self._provider(group)
        start, end = s.get("startTime"), s.get("endTime")
        err = s.get("error_information") or {}
        md = s.get("metadata") or {}
        return {
            "ts": _now(), "provider": pid, "model_group": group, "model": s.get("model"), "status": status,
            "call_id": s.get("id"), "prompt_tokens": s.get("prompt_tokens"),
            "completion_tokens": s.get("completion_tokens"), "cost_usd": s.get("response_cost") or 0.0,
            "latency_s": round(end - start, 3) if isinstance(start, (int, float)) and isinstance(end, (int, float)) else None,
            "error": (err.get("error_message") or str(kwargs.get("exception") or ""))[:500] or None,
            "caller": _logged_caller(kwargs, md),
        }

    async def async_log_success_event(self, kwargs, response_obj, start_time, end_time):
        row = self._row(kwargs, "success")
        budget.append_log(row)
        if row["provider"] in self.pacers:
            self.pacers[row["provider"]].ok()
        if row["provider"]:
            self.tracker.record(row["provider"], time.time(),
                                (row["prompt_tokens"] or 0) + (row["completion_tokens"] or 0), row["cost_usd"])

    async def async_log_failure_event(self, kwargs, response_obj, start_time, end_time):
        row = self._row(kwargs, "failure")
        budget.append_log(row)
        if row["provider"] in self.pacers and "RateLimit" in (row["error"] or ""):
            self.pacers[row["provider"]].limited()


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds")


proxy_handler_instance = HxHooks()
