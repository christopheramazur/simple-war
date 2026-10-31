"""hx providers: the provider roster with readiness, budgets and free-tier limits.

  hx providers               status table
  hx providers --checklist   setup steps for every provider that is not ready yet
"""

from __future__ import annotations


from hx import keystore, providers
from hx.output import OK, WARN, Check, Result

HELP = "Provider roster: readiness, budgets, limits (--checklist for setup steps)"


def add_args(p) -> None:
    p.add_argument("--checklist", action="store_true", help="print setup steps for providers that are not ready")


def readiness(p: providers.Provider) -> tuple[bool, str]:
    if p.kind == "api":
        missing = [k for k in p.keys if not keystore.where(k)]
        return (not missing, "keys ok" if not missing else "missing " + ", ".join(missing))
    if p.kind == "client":
        found = providers.find_cli(p)
        return (bool(found), f"{p.cli} found (login not checked)" if found else f"{p.cli} not installed")
    return True, p.kind


def run(args) -> Result:
    r = Result("providers")
    roster = providers.load()
    rows, not_ready = [], []
    for p in roster.values():
        ready, why = readiness(p)
        if not ready:
            not_ready.append(p)
        lim = p.limits or {}
        rows.append({
            "provider": p.id, "kind": p.kind, "ready": ready, "status": why,
            "budget_usd": p.monthly_budget_usd, "hard_stop": p.hard_stop,
            "free_limits": ", ".join(f"{k} {v}" for k, v in lim.items()) or "-",
            "trains": {True: "yes", False: "no", None: "?"}[p.trains_on_data],
        })
    r.tables["providers"] = rows
    r.checks.append(Check("ready", OK if not not_ready else WARN,
                          f"{len(roster) - len(not_ready)}/{len(roster)} ready"))
    if args.checklist:
        r.tables = {}
        r.data["checklist"] = "\n" + (_checklist(not_ready) if not_ready else "Every provider is ready.")
    return r


def _checklist(todo: list[providers.Provider]) -> str:
    out = []
    for i, p in enumerate(todo, 1):
        out.append(f"{i}. {p.name}  [{p.kind}]")
        for s in p.steps:
            out.append(f"   - {s}")
        if p.kind == "api":
            for k in p.keys:
                if not keystore.where(k):
                    out.append(f"   - Store it: harness/bin/hx secrets set {k}")
        if p.notes:
            out.append(f"   note: {p.notes}")
        if p.verified:
            out.append(f"   (facts checked {p.verified})")
        out.append("")
    out.append("Budgets default to $0 with hard_stop; edit config/providers.toml to allow spend.")
    return "\n".join(out)
