"""Run tasks against a target, check them, append results to data/raw/bench/<run_id>.jsonl."""

from __future__ import annotations

import json
import re
import uuid
from datetime import datetime, timezone
from functools import cache
from pathlib import Path
from typing import Callable

from hx.bench import BENCH_ROOT, SUITE_VERSION, adapters, checks
from hx.paths import data_dir

CHARS_PER_TOKEN = 4
PAD_INTRO = "Reference material follows. It may be irrelevant to the task.\n\n"
PAD_OUTRO = "\n\n---\nEnd of reference material. The task:\n\n"


def results_dir() -> Path:
    return data_dir() / "raw" / "bench"


def parse_context(spec: str) -> int:
    """'0', '8k', '32000' -> tokens."""
    m = re.fullmatch(r"(\d+)(k?)", spec.strip().lower())
    if not m:
        raise ValueError(f"bad context size {spec!r}")
    return int(m[1]) * (1000 if m[2] else 1)


@cache
def _filler() -> str:
    # Normalise line endings: git autocrlf may check this out as CRLF on Windows,
    # and padded prompts must be byte-identical on every machine.
    return (BENCH_ROOT / "filler" / "gdd.txt").read_text(encoding="utf-8").replace("\r\n", "\n")


def pad(prompt: str, context_tokens: int) -> str:
    """Prefix distractor text so the whole prompt is roughly `context_tokens` long."""
    need = context_tokens * CHARS_PER_TOKEN - len(prompt) - len(PAD_INTRO) - len(PAD_OUTRO)
    if need <= 0:
        return prompt
    text = _filler()
    while len(text) < need:
        text += "\n\n" + _filler()
    return PAD_INTRO + text[:need] + PAD_OUTRO + prompt


def run(target_name: str, target: dict, tasks: list[dict], contexts: list[int], repeat: int = 1,
        timeout: float = 900, on_result: Callable[[dict], None] | None = None) -> tuple[str, Path]:
    run_id = datetime.now().strftime("%Y%m%d-%H%M%S-") + uuid.uuid4().hex[:4]
    out = results_dir() / f"{run_id}.jsonl"
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("a", encoding="utf-8") as f:
        for ctx in contexts:
            for task in tasks:
                for rep in range(repeat):
                    reply = adapters.call(target, task["system"], pad(task["prompt"], ctx), timeout)
                    score, passed, detail = (0.0, False, reply.error) if reply.error else checks.check(task, reply.text)
                    row = {
                        "run_id": run_id, "ts": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                        "suite_version": SUITE_VERSION, "target": target_name, "adapter": target["adapter"],
                        "model": target.get("model"), "thinking": target.get("thinking"),
                        "task_id": task["id"], "level": task["level"], "task_class": task["task_class"],
                        "size": task["size"], "context_tokens": ctx, "repeat": rep,
                        "passed": passed, "score": round(score, 4), "detail": detail, "error": reply.error,
                        "latency_s": reply.latency_s, "input_tokens": reply.input_tokens,
                        "output_tokens": reply.output_tokens, **reply.extra,
                        "output": reply.text,  # full text: failures need inspecting
                    }
                    f.write(json.dumps(row) + "\n")
                    f.flush()
                    if on_result:
                        on_result(row)
    return run_id, out
