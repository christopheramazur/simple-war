"""hx: the single entry point for the harness (DESIGN.md §1).

Each verb lives in hx.commands.<verb> and exposes:
    HELP: str
    add_args(parser) -> None      (optional)
    run(args) -> hx.output.Result
"""

from __future__ import annotations

import argparse
import importlib
import sys

from hx import __version__

VERBS = ["status", "doctor", "ingest", "report", "bench", "providers", "secrets"]


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="hx", description="Simple War agent harness")
    p.add_argument("--version", action="version", version=f"hx {__version__}")
    sub = p.add_subparsers(dest="verb", required=True, metavar="<verb>")
    for name in VERBS:
        mod = importlib.import_module(f"hx.commands.{name}")
        sp = sub.add_parser(name, help=mod.HELP, description=mod.HELP)
        sp.add_argument("--json", action="store_true", help="machine-readable output")
        sp.add_argument("-v", "--verbose", action="store_true", help="show passing checks too")
        if hasattr(mod, "add_args"):
            mod.add_args(sp)
        sp.set_defaults(_mod=mod)
    return p


def main(argv: list[str] | None = None) -> int:
    # Windows consoles default to cp1252; keep output UTF-8 for agents.
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")
    args = build_parser().parse_args(argv)
    result = args._mod.run(args)
    print(result.to_json() if args.json else result.to_text(verbose=args.verbose))
    return result.exit_code


if __name__ == "__main__":
    sys.exit(main())
