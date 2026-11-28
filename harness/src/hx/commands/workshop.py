"""hx workshop: list and run the behaviour-workshop scenarios in one call (U1 B5, sw-tho3.5).

  hx workshop list                                    one row per scenario file in data/sim/workshop/
  hx workshop run <id> | --all [--variant V] [--trace] [--json] [--timeout S]

run starts src/api/workshop/workshop_cli.gd headless through hx godot run's plumbing and reads its
--json report (data/sim/workshop/README.md, schema 1). Text output: one line per scenario, failures
first; each failing probe or comparison is listed under its scenario. --trace also lists every
passing, pending and unexpected-pass check. Exit 1 only when a gate check fails or a scenario cannot
load or run; pending checks never do. Exit 2 is a usage error (unknown id, or an id together with --all).
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from hx import paths
from hx.commands import godot as godot_cmd
from hx.output import FAIL, OK, Check, Result

HELP = "Behaviour workshop: list scenarios, or run one or all headless (failures first, one line each)"
SCHEMA = 1  # data/sim/workshop/README.md, "--json schema (frozen; version 1)"
BEGIN, END = "WORKSHOP_JSON_BEGIN", "WORKSHOP_JSON_END"
CLI = "res://src/api/workshop/workshop_cli.gd"
TIMEOUT = 900
TAIL = 15  # output lines shown when no report came back
RANK = {"error": 0, "fail": 1, "pass": 2}  # failures sort first
BAD = ("fail", "error")  # probe and comparison results that fail the gate
LABEL = {"pass": "ok", "fail": "FAIL", "error": "ERROR", "pending": "pending",
         "unexpected_pass": "UNEXPECTED PASS", "report": "report"}


def add_args(p) -> None:
    sub = p.add_subparsers(dest="action", required=True, metavar="<action>")
    ls = sub.add_parser("list", help="scenario files with status, component and check counts")
    rn = sub.add_parser("run", help="run one scenario (id) or all of them (--all)")
    rn.add_argument("scenario", nargs="?", help="scenario id: its file name without .json")
    rn.add_argument("--all", action="store_true", help="every scenario in data/sim/workshop/")
    rn.add_argument("--variant", help="run only this variant (comparisons that need another are skipped)")
    rn.add_argument("--trace", action="store_true", help="also list every passing, pending and report-only check")
    rn.add_argument("--timeout", type=float, default=TIMEOUT, help=f"seconds for the Godot run (default {TIMEOUT})")
    for sp in (ls, rn):  # also accepted after the action, as hx godot does
        sp.add_argument("--json", action="store_true", default=argparse.SUPPRESS)
        sp.add_argument("-v", "--verbose", action="store_true", default=argparse.SUPPRESS)


def run(args) -> Result:
    return _list() if args.action == "list" else _run(args)


def scenario_dir(root: Path | None = None) -> Path:
    return (root or paths.repo_root()) / "data" / "sim" / "workshop"


def scenario_rows(directory: Path) -> tuple[list[dict], list[str]]:
    """One row per readable scenario file, and a message for each file that is not one."""
    rows, bad = [], []
    for f in sorted(directory.glob("*.json")):
        try:
            d = json.loads(f.read_text(encoding="utf-8"))
        except (OSError, ValueError) as e:
            bad.append(f"{f.name}: {e}")
            continue
        if not isinstance(d, dict) or d.get("id") != f.stem:
            bad.append(f"{f.name}: id must match the file name ({f.stem})")
            continue
        rows.append({"id": d["id"], "status": d.get("status", "gate"), "component": d.get("component", "-"),
                     "variants": len(d.get("variants") or {}) + 1,  # plus base
                     "probes": len(d.get("probes") or []), "compares": len(d.get("compare") or [])})
    return rows, bad


def _list() -> Result:
    r = Result("workshop")
    directory = scenario_dir()
    if not directory.is_dir():
        r.checks.append(Check("scenarios", FAIL, f"no directory {directory}"))
        return r
    rows, bad = scenario_rows(directory)
    r.tables["scenarios"] = rows
    r.data["count"] = len(rows)
    r.checks += [Check("scenario file", FAIL, b) for b in bad]
    return r


def _usage(r: Result, msg: str) -> Result:
    r.checks.append(Check("usage", FAIL, msg))
    r.exit_override = 2
    return r


def _run(args) -> Result:
    r = Result("workshop")
    if bool(args.all) == bool(args.scenario):
        return _usage(r, "give one scenario id, or --all (not both)")
    if args.scenario and not (scenario_dir() / f"{args.scenario}.json").is_file():
        return _usage(r, f"no scenario '{args.scenario}' (see hx workshop list)")
    root, exe = godot_cmd._console()
    if root is None:
        r.checks.append(Check("godot", FAIL, exe))
        return r
    extra = ["--scenario", "all" if args.all else args.scenario]
    if args.variant:
        extra += ["--variant", args.variant]
    extra += ["--json"]  # last: workshop_cli reads a value after a flag that is not followed by --
    code, lines = godot_cmd._run(exe, root, godot_cmd.run_args(CLI, False, None, extra), args.timeout)
    try:
        report = parse_report(lines)
    except ValueError as e:
        tail = [x for x in lines if x.strip()][-TAIL:]
        errs = godot_cmd.errors(lines)
        hint = "; Godot could not load the scripts: run hx godot check (imports the project) first" if errs else ""
        r.checks.append(Check("godot", FAIL, "timed out" if code == godot_cmd.TIMED_OUT else
                              f"no usable report (exit {code}): {e}{hint}"))
        r.data["output"] = "\n  " + "\n  ".join(tail)
        return r
    scenarios = sorted(report["scenarios"], key=lambda s: (RANK.get(s["result"], 0), s["scenario"]))
    for s in scenarios:
        r.checks.append(Check(s["scenario"], OK if s["result"] == "pass" else FAIL, s["result"]))
    r.data.update(schema=report["schema"], scenarios=scenarios)
    out: list[str] = []
    for s in scenarios:
        out += scenario_lines(s, args.trace)
    r.raw = "\n".join(out) if out else "no scenarios in data/sim/workshop/"
    return r


def parse_report(lines: list[str]) -> dict:
    """The report between the markers. Raises ValueError when it is missing or not schema 1."""
    if BEGIN not in lines or END not in lines[lines.index(BEGIN):]:
        raise ValueError(f"no {BEGIN}..{END} block")
    i = lines.index(BEGIN)
    body = lines[i + 1:lines.index(END, i + 1)]
    try:
        d = json.loads("".join(body))
    except ValueError as e:
        raise ValueError(f"report is not JSON ({e})") from None
    if not isinstance(d, dict) or d.get("schema") != SCHEMA or not isinstance(d.get("scenarios"), list):
        raise ValueError(f"report is not schema {SCHEMA}")
    return d


def scenario_lines(s: dict, trace: bool) -> list[str]:
    """One line per scenario; failing checks follow it. A passing scenario with no trace is one line."""
    first = s["variants"][0] if s["variants"] else {"name": "-", "hash": ""}
    out = [f"{s['result'].upper()} {s['scenario']} [{s['status']}] {first['name']} {first.get('hash', '')[:8]}"
           f" gate_failures={s['gate_failures']} pending={s['pending']}"]
    out += [f"    {e}" for e in s["errors"]]
    for v in s["variants"]:
        out += [f"    {v['name']}: {e}" for e in v.get("errors", [])]
        out += [_probe_line(v["name"], p) for p in v.get("probes", []) if p["result"] in BAD or trace]
    out += [_compare_line(c) for c in s.get("compare", []) if c["result"] in BAD or trace]
    return out


def _probe_line(variant: str, p: dict) -> str:
    text = f"    {LABEL.get(p['result'], p['result'])} {variant}.{p['id']} ({p['kind']} {p['when']}): " \
           f"{_val(p['value'])} expect {_val(p['expect'])}"
    return text + (f" - {p['error']}" if p.get("error") else "")


def _compare_line(c: dict) -> str:
    return f"    {LABEL.get(c['result'], c['result'])} compare {c['metric']}: {c['lhs']} {_val(c['lhs_value'])} " \
           f"{c['rel']} {_val(c['factor'])} x {c['rhs']} {_val(c['rhs_value'])}"


def _val(v) -> str:
    return v if isinstance(v, str) else json.dumps(v, separators=(",", ":"))
