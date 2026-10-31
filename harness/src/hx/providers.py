"""Provider roster, budgets and free-tier limits (config/providers.toml; DESIGN.md §4, Q24/Q30/Q37)."""

from __future__ import annotations

import tomllib
from dataclasses import dataclass, field
from pathlib import Path

from hx.paths import HARNESS_ROOT

PROVIDERS_FILE = HARNESS_ROOT / "config" / "providers.toml"
KINDS = {"subscription", "api", "local", "client"}  # client = usable only inside its own CLI


@dataclass
class Provider:
    id: str
    name: str
    kind: str
    keys: list[str] = field(default_factory=list)
    monthly_budget_usd: float = 0.0
    hard_stop: bool = True
    alert_at: list[int] = field(default_factory=lambda: [50, 80, 100])
    trains_on_data: bool | None = None
    limits: dict = field(default_factory=dict)
    reset_tz: str | None = None
    base_url: str | None = None
    litellm_prefix: str | None = None
    cli: str | None = None
    signup_url: str | None = None
    key_url: str | None = None
    steps: list[str] = field(default_factory=list)
    notes: str | None = None
    verified: str | None = None
    # Gateway deployments: [{alias, model, params?}]. alias is served as "<provider>/<alias>".
    models: list[dict] = field(default_factory=list)


def load(path: Path | None = None) -> dict[str, Provider]:
    data = tomllib.loads((path or PROVIDERS_FILE).read_text(encoding="utf-8")).get("provider", {})
    out = {}
    for pid, d in data.items():
        if d.get("kind") not in KINDS:
            raise ValueError(f"provider {pid}: kind must be one of {sorted(KINDS)}")
        if d.get("monthly_budget_usd", 0) < 0:
            raise ValueError(f"provider {pid}: negative budget")
        out[pid] = Provider(id=pid, **d)
    return out
