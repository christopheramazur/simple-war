"""hx gateway: the local LiteLLM gateway (DESIGN.md §4).

  hx gateway start | stop | status
  hx gateway config               regenerate data/gateway/litellm.yaml from providers.toml
  hx gateway discover <provider>  list the provider's models (needs its key) to fill `models`
"""

from __future__ import annotations

import argparse
import json
import time
import urllib.error
import urllib.request

from hx import keystore, providers
from hx.gateway import budget, config, process
from hx.output import FAIL, OK, WARN, Check, Result

HELP = "Local LLM gateway: start | stop | status | config | discover"


def add_args(p) -> None:
    sub = p.add_subparsers(dest="action", required=True, metavar="<action>")
    for name in ("start", "stop", "status", "config", "discover"):
        sp = sub.add_parser(name)
        sp.add_argument("--json", action="store_true", default=argparse.SUPPRESS)
        sp.add_argument("-v", "--verbose", action="store_true", default=argparse.SUPPRESS)
        if name == "discover":
            sp.add_argument("provider")
            sp.add_argument("--free", action="store_true", help="only free models (OpenRouter ':free')")


def run(args) -> Result:
    return {"start": _start, "stop": _stop, "status": _status, "config": _config,
            "discover": _discover}[args.action](args)


def _start(args) -> Result:
    r = Result("gateway start")
    ok, msg = process.start()
    r.data.update({"url": process.base_url() + "/v1", "log": str(process.log_file())})
    r.checks.append(Check("gateway", OK if ok else FAIL, msg))
    return r


def _stop(args) -> Result:
    r = Result("gateway stop")
    r.data["result"] = process.stop()
    return r


def _config(args) -> Result:
    r = Result("gateway config")
    path, skipped, n = config.write()
    r.data.update({"config": str(path), "models": n})
    if skipped:
        r.checks.append(Check("providers skipped", WARN, "; ".join(skipped)))
    return r


def _status(args) -> Result:
    r = Result("gateway status")
    roster = providers.load()
    up = process.alive()
    r.data["url"] = process.base_url() + "/v1"
    r.checks.append(Check("running", OK if up else WARN, "" if up else "not running; hx gateway start"))
    models, skipped = config.deployments(roster)
    r.data["models"] = [m["model_name"] for m in models]
    t = budget.Tracker(roster)
    rows = budget.read_log()
    t.seed(rows)
    now = time.time()
    usage = []
    for pid, p in roster.items():
        if p.kind not in ("api", "local"):
            continue
        snap = t.snapshot().get(pid, {})
        refused = sum(1 for x in rows if x.get("provider") == pid and x.get("status") == "refused")
        usage.append({"provider": pid, "today_requests": snap.get("day", {}).get("requests", 0),
                      "today_tokens": snap.get("day", {}).get("tokens", 0),
                      "month_usd": round(snap.get("month", {}).get("usd", 0.0), 4),
                      "budget_usd": p.monthly_budget_usd, "refused_32d": refused,
                      "gate": "open" if t.check(pid, now).allowed else t.check(pid, now).reason})
    r.tables["usage"] = usage
    if skipped:
        r.checks.append(Check("providers skipped", WARN, "; ".join(skipped)))
    return r


def _discover(args) -> Result:
    r = Result("gateway discover")
    p = providers.load().get(args.provider)
    if p is None or not p.base_url or "{" in p.base_url:
        r.checks.append(Check("provider", FAIL, "unknown provider or no plain OpenAI-compatible base_url"))
        return r
    key = next((keystore.get(k) for k in p.keys if k.endswith(("_API_KEY", "_TOKEN"))), None)
    if p.keys and not key:
        r.checks.append(Check("key", FAIL, f"store it first: hx secrets set {p.keys[0]}"))
        return r
    req = urllib.request.Request(p.base_url.rstrip("/") + "/models",
                                 headers={"Authorization": f"Bearer {key}"} if key else {})
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            ids = sorted(m.get("id", "") for m in json.loads(resp.read()).get("data", []))
    except (urllib.error.URLError, OSError, ValueError) as e:
        r.checks.append(Check("request", FAIL, str(e)[:200]))
        return r
    if args.free:
        ids = [i for i in ids if i.endswith(":free")]
    r.data["count"] = len(ids)
    r.tables["models"] = [{"id": i} for i in ids]
    return r
