"""Automatic checkers. Each returns (score 0..1, passed, detail).

Checks never use an LLM: a task passes only on a mechanically verifiable result.
"""

from __future__ import annotations

import json
import re
from functools import cache

from hx.bench import BENCH_ROOT

_THINK = re.compile(r"<think>.*?</think>", re.S | re.I)
_FENCE = re.compile(r"```[\w-]*\s*\n(.*?)```", re.S)


def extract(text: str) -> str:
    """Strip reasoning blocks and take the last fenced block if any."""
    text = _THINK.sub("", text or "")
    if "</think>" in text:  # unterminated opening tag stripped by the server
        text = text.split("</think>")[-1]
    blocks = _FENCE.findall(text)
    return (blocks[-1] if blocks else text).strip()


def _json(text: str):
    s = extract(text)
    try:
        return json.loads(s)
    except json.JSONDecodeError:
        # Tolerate prose around a single JSON value.
        m = re.search(r"(\[.*\]|\{.*\})", s, re.S)
        if m:
            return json.loads(m.group(1))
        raise


def check(task: dict, output: str) -> tuple[float, bool, str]:
    c = task["check"]
    fn = CHECKERS[c["type"]]
    try:
        return fn(c, output)
    except (json.JSONDecodeError, ValueError, TypeError, KeyError, AttributeError) as e:
        return 0.0, False, f"unparseable: {type(e).__name__}: {str(e)[:120]}"


def _json_equal(c, output):
    got, exp = _json(output), c["expected"]
    if got == exp:
        return 1.0, True, "exact"
    if isinstance(got, list) and isinstance(exp, list):
        same = sum(1 for g, e in zip(got, exp) if g == e)
        return same / max(len(exp), 1), False, f"{same}/{len(exp)} items equal, got {len(got)} items"
    return 0.0, False, "mismatch"


def _table_rows(text: str) -> list[list[str]]:
    rows = []
    for line in extract(text).splitlines():
        line = line.strip()
        if not line.startswith("|") and "|" not in line:
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if all(re.fullmatch(r":?-{2,}:?", c) for c in cells if c):
            continue  # separator row
        rows.append(cells)
    return rows


def _table_equal(c, output):
    got, exp = _table_rows(output), c["expected"]
    if got == exp:
        return 1.0, True, "exact"
    same = sum(1 for g, e in zip(got, exp) if g == e)
    return same / len(exp), False, f"{same}/{len(exp)} rows equal, got {len(got)} rows"


def _set_equal(c, output):
    got = _json(output)
    got = set(got[c["key"]] if isinstance(got, dict) else got)
    exp = set(c["expected"])
    jac = len(got & exp) / len(got | exp) if got | exp else 1.0
    return jac, got == exp, f"missing {sorted(exp - got)[:5]} extra {sorted(got - exp)[:5]}"


def _labels(c, output):
    got, exp = _json(output), c["expected"]
    right = [k for k, v in exp.items() if str(got.get(k, "")).strip().lower() == v]
    acc = len(right) / len(exp)
    wrong = [f"{k}={got.get(k)!r}" for k in exp if k not in right][:6]
    return acc, acc >= c.get("pass_at", 1.0), f"{len(right)}/{len(exp)} correct" + (f"; wrong {wrong}" if wrong else "")


@cache
def _schema(name: str):
    return json.loads((BENCH_ROOT / "schemas" / name).read_text(encoding="utf-8"))


def _attacks(c, output):
    from jsonschema import Draft202012Validator

    got = _json(output)
    if not isinstance(got, list):
        return 0.0, False, "not a JSON array"
    validator = Draft202012Validator(_schema(c["schema"]))
    exp = c["expected"]
    ok, problems = 0, []
    for i, e in enumerate(exp):
        g = got[i] if i < len(got) else None
        errs = [] if g is None else [er.message for er in validator.iter_errors(g)]
        fields_ok = g is not None and all(g.get(k) == v for k, v in e.items())
        if g is not None and not errs and fields_ok:
            ok += 1
        elif len(problems) < 4:
            problems.append(f"#{i} {e['id']}: " + ("missing" if g is None else "; ".join(errs[:2]) or "field mismatch"))
    passed = ok == len(exp) and len(got) == len(exp)
    detail = f"{ok}/{len(exp)} entries correct, got {len(got)}" + (f"; {problems}" if problems else "")
    return ok / len(exp), passed, detail


CHECKERS = {"json_equal": _json_equal, "table_equal": _table_equal, "set_equal": _set_equal,
            "labels": _labels, "attacks": _attacks}
