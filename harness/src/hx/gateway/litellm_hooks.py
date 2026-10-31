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


class HxHooks(CustomLogger):
    def __init__(self):
        super().__init__()
        self.roster = providers.load()
        self.aliases = config.alias_map(self.roster)  # "groq/llama70b" -> "groq"
        self.tracker = budget.Tracker(self.roster)
        self.tracker.seed(budget.read_log())

    def _provider(self, model: str | None) -> str | None:
        return self.aliases.get(model or "")

    async def async_pre_call_hook(self, user_api_key_dict, cache, data: dict, call_type):
        model = data.get("model")
        pid = self._provider(model)
        if pid is None:
            raise HTTPException(status_code=404, detail=f"unknown model {model!r}; see hx gateway status")
        d = self.tracker.check(pid, time.time())
        if not d.allowed:
            budget.append_log({"ts": _now(), "provider": pid, "model_group": model, "status": "refused",
                               "error": d.reason})
            raise HTTPException(status_code=429, detail=d.reason)
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
            "caller": (md.get("headers") or {}).get("x-hx-caller") if isinstance(md.get("headers"), dict) else None,
        }

    async def async_log_success_event(self, kwargs, response_obj, start_time, end_time):
        row = self._row(kwargs, "success")
        budget.append_log(row)
        if row["provider"]:
            self.tracker.record(row["provider"], time.time(),
                                (row["prompt_tokens"] or 0) + (row["completion_tokens"] or 0), row["cost_usd"])

    async def async_log_failure_event(self, kwargs, response_obj, start_time, end_time):
        budget.append_log(self._row(kwargs, "failure"))


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds")


proxy_handler_instance = HxHooks()
