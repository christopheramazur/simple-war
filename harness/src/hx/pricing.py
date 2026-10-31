"""Price table (config/prices.toml) and the per-call USD estimate."""

from __future__ import annotations

import tomllib
from dataclasses import dataclass
from pathlib import Path

from hx.paths import HARNESS_ROOT

PRICES_FILE = HARNESS_ROOT / "config" / "prices.toml"
CATEGORIES = ("input", "cache_write_5m", "cache_write_1h", "cache_read", "output")


@dataclass(frozen=True)
class Price:
    prefix: str
    provider: str
    rates: dict[str, float]
    long_threshold: int | None = None
    long_rates: dict[str, float] | None = None


def load(path: Path = PRICES_FILE) -> list[Price]:
    data = tomllib.loads(path.read_text(encoding="utf-8"))
    out = []
    for m in data.get("model", []):
        long_rates = {c: m[f"long_{c}"] for c in CATEGORIES} if "long_threshold" in m else None
        out.append(Price(m["prefix"], m["provider"], {c: m[c] for c in CATEGORIES},
                         m.get("long_threshold"), long_rates))
    # Longest prefix wins: "claude-opus-5-5" before "claude-opus-5".
    return sorted(out, key=lambda p: len(p.prefix), reverse=True)


def match(prices: list[Price], model: str | None) -> Price | None:
    if not model:
        return None
    return next((p for p in prices if model.startswith(p.prefix)), None)


def estimate(price: Price | None, tokens: dict[str, int]) -> float | None:
    """USD for one call. `tokens` is keyed by CATEGORIES."""
    if price is None:
        return None
    rates = price.rates
    if price.long_threshold is not None:
        prompt = sum(tokens.get(c, 0) for c in CATEGORIES if c != "output")
        if prompt > price.long_threshold:
            rates = price.long_rates
    return sum(tokens.get(c, 0) * rates[c] for c in CATEGORIES) / 1_000_000
