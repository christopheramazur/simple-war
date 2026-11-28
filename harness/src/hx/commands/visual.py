"""hx visual: visual assessment of battle captures (U1, draft 02 §5.6). Only `lint` exists yet.

  hx visual lint <layout.json | capture-dir | mock-dir> [--png IMAGE] [--strict]

lint runs the model-free layout checks (hx/visual.py): label against label overlap, a label over
another squad's footprint, squads' footprints overlapping, and label text contrast against the
ground under it (WCAG ratio). A capture folder is read from its layout/*.json; a mock's output folder
from its *_layout.json. Findings are warnings and exit 0; --strict exits 1 when there are any.
Exit 2 is a usage error (no layout found).
"""

from __future__ import annotations

import argparse
from pathlib import Path

from hx import visual
from hx.output import FAIL, OK, WARN, Check, Result

HELP = "Visual assessment of battles: lint a capture's layout for overlapping labels and low contrast (no model)"


def add_args(p) -> None:
    sub = p.add_subparsers(dest="action", required=True, metavar="<action>")
    ln = sub.add_parser("lint", help="model-free layout checks on a capture or a layout JSON")
    ln.add_argument("path", help="a layout JSON, a capture folder, or a mock output folder")
    ln.add_argument("--png", help="the image to sample for contrast (default: the layout's own image)")
    ln.add_argument("--strict", action="store_true", help="exit 1 when any layout has findings")
    # also accepted after the action, as hx godot does
    ln.add_argument("--json", action="store_true", default=argparse.SUPPRESS)
    ln.add_argument("-v", "--verbose", action="store_true", default=argparse.SUPPRESS)


def run(args) -> Result:
    r = Result("visual")
    target = Path(args.path)
    files = visual.layout_files(target) if target.exists() else []
    if not files:
        r.checks.append(Check("layout", FAIL, f"no layout JSON under {target}"))
        r.exit_override = 2
        return r
    png = Path(args.png) if args.png else None
    total = 0
    for f in files:
        res = visual.lint_file(f, png)
        n = len(res["findings"])
        total += n
        name = f.name
        if not res["contrast"]:
            r.checks.append(Check(f"{name}: contrast", WARN, "not checked: no image (pass --png)"))
        r.checks.append(Check(f"{name}: {n} finding(s)", OK if n == 0 else WARN,
                              f"{res['boxes']} boxes, image {res['image'] or 'none'}"))
        for x in res["findings"]:
            squads = ",".join(str(s) for s in x["squads"])
            r.checks.append(Check(f"{name} {x['check']}", WARN,
                                  f"frame {x['frame']} squads {squads}: {x['detail']} at {x['rect']}"))
    r.data = {"layouts": len(files), "findings": total}
    if args.strict and total:
        r.exit_override = 1
    return r
