"""Display time for the harness. Every time a person reads (logs, bead notes, status pages, agent prompts, reports) is
AEST: UTC+10, the owner's zone (Brisbane, no daylight saving), labelled "AEST" or written with a +10:00 offset.

Stored timestamps that code compares or parses back (the DuckDB ledger, filenames like 20261128T010000Z, provider
quota resets in config/providers.toml) stay UTC or in their own zone; convert them with `local()` when showing them.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

AEST = timezone(timedelta(hours=10), "AEST")


def now() -> datetime:
    return datetime.now(AEST)


def local(t: datetime | float | int | None = None) -> datetime:
    """`t` in AEST: an epoch, an aware datetime, or a naive one (taken as UTC, the ledger's convention); None is now."""
    if t is None:
        return now()
    if isinstance(t, (int, float)):
        return datetime.fromtimestamp(t, AEST)
    if t.tzinfo is None:
        t = t.replace(tzinfo=timezone.utc)
    return t.astimezone(AEST)


def stamp(t: datetime | float | int | None = None, fmt: str = "%Y-%m-%d %H:%M") -> str:
    """'2026-11-28 11:05 AEST'."""
    return f"{local(t):{fmt}} AEST"
