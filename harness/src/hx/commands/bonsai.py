"""hx bonsai: the local Bonsai llama-server.

  hx bonsai start [--ctx N] | stop | status
  hx bonsai probe [--sizes 200k,128k,96k,64k,32k] [--apply]   find the largest context that fits at full speed
"""

from __future__ import annotations

import argparse
import sys

from hx import localmodel, providers
from hx.output import FAIL, OK, WARN, Check, Result

HELP = "Local Bonsai server: start | stop | status | probe"
PID = "bonsai"


def add_args(p) -> None:
    sub = p.add_subparsers(dest="action", required=True, metavar="<action>")
    for name in ("start", "stop", "status", "probe"):
        sp = sub.add_parser(name)
        sp.add_argument("--json", action="store_true", default=argparse.SUPPRESS)
        sp.add_argument("-v", "--verbose", action="store_true", default=argparse.SUPPRESS)
        if name == "start":
            sp.add_argument("--ctx", type=int, help="override the configured context size")
        if name == "probe":
            sp.add_argument("--sizes", default="200k,160k,128k,96k,64k,32k",
                            help="context sizes to try, largest first")
            sp.add_argument("--fill", type=float, default=0.9, help="fraction of each context to fill (default 0.9)")
            sp.add_argument("--apply", action="store_true", help="write the chosen ctx to config/providers.toml")


def _size(s: str) -> int:
    s = s.strip().lower()
    return int(s[:-1]) * 1024 if s.endswith("k") else int(s)


def run(args) -> Result:
    r = Result(f"bonsai {args.action}")
    if args.action == "start":
        ok, msg = localmodel.start(PID, args.ctx)
        r.data["url"] = localmodel.url(PID) + "/v1"
        r.checks.append(Check("server", OK if ok else FAIL, msg))
    elif args.action == "stop":
        r.data["result"] = localmodel.stop(PID)
    elif args.action == "status":
        up = localmodel.alive(PID)
        p = providers.load()[PID]
        r.data.update({"url": localmodel.url(PID) + "/v1", "configured_ctx": p.server.get("ctx"),
                       "vram_used_mib": localmodel.vram_used_mib(), "vram_total_mib": localmodel.vram_total_mib()})
        r.checks.append(Check("running", OK if up else WARN, "" if up else "not running; hx bonsai start"))
    elif args.action == "probe":
        if localmodel.alive(PID):
            r.checks.append(Check("probe", FAIL, "server already running; hx bonsai stop first"))
            return r
        results = []
        for size in [_size(s) for s in args.sizes.split(",")]:
            print(f"probing ctx {size} ...", file=sys.stderr, flush=True)
            res = localmodel.probe_one(PID, size, args.fill)
            print(f"  loaded={res.loaded} fill_ok={res.fill_ok} gen={res.gen_tps} t/s "
                  f"prefill={res.prefill_tps} t/s vram={res.vram_mib} MiB {res.error or ''}"[:220],
                  file=sys.stderr, flush=True)
            results.append(res)
        chosen = localmodel.choose(results)
        out = localmodel.save_probe(PID, results, chosen)
        r.tables["probe"] = [{"ctx": x.ctx, "loaded": x.loaded, "filled": x.fill_ok, "filled_tokens": x.filled_tokens,
                              "gen_tps": x.gen_tps, "prefill_tps": x.prefill_tps, "vram_mib": x.vram_mib,
                              "secs": x.seconds} for x in results]
        r.data.update({"chosen_ctx": chosen, "saved": str(out)})
        if chosen and args.apply:
            localmodel.apply_ctx(PID, chosen)
            r.data["applied"] = "config/providers.toml"
        r.checks.append(Check("fit", OK if chosen else FAIL, "" if chosen else "no size loaded and filled"))
    return r
