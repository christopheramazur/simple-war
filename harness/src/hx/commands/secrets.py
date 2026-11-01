"""hx secrets: store and check provider API keys (values are never printed).

  hx secrets set OPENROUTER_API_KEY     prompts without echo (run it yourself in a terminal)
  hx secrets set NAME --stdin           read the value from stdin (e.g. piped from a password manager)
  hx secrets list                       which keys exist and where (env / keyring / file)
  hx secrets delete NAME
  hx secrets export NAME --user-env     copy a stored key into your Windows user environment (not shown);
                                        apps started afterwards see it (e.g. the OpenCode desktop app)
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
    for name in ("set", "list", "delete", "export"):
        sp = sub.add_parser(name)
        sp.add_argument("--json", action="store_true", default=argparse.SUPPRESS)
        sp.add_argument("-v", "--verbose", action="store_true", default=argparse.SUPPRESS)
        if name in ("set", "delete", "export"):
            sp.add_argument("name", help="UPPER_SNAKE_CASE key name, e.g. OPENROUTER_API_KEY")
        if name == "set":
            sp.add_argument("--file", action="store_true", help="store in ~/.hx/secrets.env instead of the OS keyring")
            sp.add_argument("--stdin", action="store_true", help="read the value from stdin")
        if name == "export":
            sp.add_argument("--user-env", action="store_true", required=True,
                            help="set it as a persistent user environment variable (HKCU Environment)")


def run(args) -> Result:
    return {"set": _set, "list": _list, "delete": _delete, "export": _export}[args.action](args)


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
        if not p.enabled:
            continue
        for k in p.keys:
            seen.add(k)
            rows.append({"key": k, "provider": p.id, "source": keystore.where(k) or "missing"})
    for k in ("HX_GATEWAY_KEY",):  # harness's own keys (generated on first gateway start)
        seen.add(k)
        rows.append({"key": k, "provider": "(gateway)", "source": keystore.where(k) or "missing"})
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


def _export(args) -> Result:
    """Write a stored key to the user environment (HKCU Environment) and broadcast the change;
    the value is never printed."""
    r = Result("secrets export")
    value = keystore.get(args.name)
    if not value:
        r.checks.append(Check("key", FAIL, f"{args.name} is not stored; hx secrets list"))
        return r
    if sys.platform != "win32":
        r.checks.append(Check("platform", FAIL, "user-env export is Windows-only; add it to your shell profile"))
        return r
    import ctypes
    import winreg
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment", 0, winreg.KEY_SET_VALUE) as k:
        winreg.SetValueEx(k, args.name, 0, winreg.REG_SZ, value.strip())
    # WM_SETTINGCHANGE so Explorer (and apps it launches next) pick up the new variable.
    ctypes.windll.user32.SendMessageTimeoutW(0xFFFF, 0x001A, 0, "Environment", 0x0002, 5000, None)
    r.data.update({"exported": args.name, "to": "user environment", "length": len(value.strip()),
                   "next": "restart the app that needs it (quit it fully, including from the tray)"})
    r.checks.append(Check("export", OK))
    return r
