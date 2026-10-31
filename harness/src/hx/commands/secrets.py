"""hx secrets: store and check provider API keys (values are never printed).

  hx secrets set OPENROUTER_API_KEY     prompts without echo (run it yourself in a terminal)
  hx secrets set NAME --stdin           read the value from stdin (e.g. piped from a password manager)
  hx secrets list                       which keys exist and where (env / keyring / file)
  hx secrets delete NAME
"""

from __future__ import annotations

import argparse
import getpass
import sys

from hx import keystore, providers
from hx.output import FAIL, OK, WARN, Check, Result

HELP = "Store/check provider API keys (OS keyring; never printed)"


def add_args(p) -> None:
    sub = p.add_subparsers(dest="action", required=True, metavar="<action>")
    for name in ("set", "list", "delete"):
        sp = sub.add_parser(name)
        sp.add_argument("--json", action="store_true", default=argparse.SUPPRESS)
        sp.add_argument("-v", "--verbose", action="store_true", default=argparse.SUPPRESS)
        if name in ("set", "delete"):
            sp.add_argument("name", help="UPPER_SNAKE_CASE key name, e.g. OPENROUTER_API_KEY")
        if name == "set":
            sp.add_argument("--file", action="store_true", help="store in ~/.hx/secrets.env instead of the OS keyring")
            sp.add_argument("--stdin", action="store_true", help="read the value from stdin")


def run(args) -> Result:
    return {"set": _set, "list": _list, "delete": _delete}[args.action](args)


def _set(args) -> Result:
    r = Result("secrets set")
    if args.stdin:
        value = sys.stdin.readline()
    elif sys.stdin.isatty():
        value = getpass.getpass(f"{args.name} (input hidden): ")
    else:
        r.checks.append(Check("input", FAIL, "no terminal; run this yourself, or pass --stdin"))
        return r
    try:
        backend = keystore.set(args.name, value, "file" if args.file else "keyring")
    except (ValueError, RuntimeError) as e:
        r.checks.append(Check("store", FAIL, str(e)))
        return r
    r.data.update({"stored": args.name, "backend": backend, "length": len(value.strip())})
    known = {k for p in providers.load().values() for k in p.keys}
    if args.name not in known:
        r.checks.append(Check("name", WARN, "not referenced by any provider in config/providers.toml"))
    return r


def _list(args) -> Result:
    r = Result("secrets list")
    r.data["keyring"] = keystore.keyring_backend()
    r.data["fallback_file"] = str(keystore.secrets_file())
    rows = []
    seen = set()
    for p in providers.load().values():
        for k in p.keys:
            seen.add(k)
            rows.append({"key": k, "provider": p.id, "source": keystore.where(k) or "missing"})
    for k in keystore.file_names():
        if k not in seen:
            rows.append({"key": k, "provider": "(unreferenced)", "source": keystore.where(k) or "missing"})
    r.tables["keys"] = rows
    missing = [x["key"] for x in rows if x["source"] == "missing"]
    r.checks.append(Check("keys", WARN if missing else OK,
                          f"{len(missing)} missing: {', '.join(missing)}" if missing else "all present"))
    return r


def _delete(args) -> Result:
    r = Result("secrets delete")
    removed = keystore.delete(args.name)
    r.data["removed_from"] = removed or "nothing stored"
    return r
