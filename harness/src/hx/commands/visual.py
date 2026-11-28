"""hx visual: visual assessment of battle captures (U1, draft 02 §5.6). `lint` (layout checks) and `diff` (golden images).

  hx visual lint <layout.json | capture-dir | mock-dir> [--png IMAGE] [--strict]
  hx visual diff <capture> --golden NAME [--accept] [--metric exact|ssim]

lint runs the model-free layout checks (hx/visual.py): label against label overlap, a label over
another squad's footprint, squads' footprints overlapping, and label text contrast against the
ground under it (WCAG ratio). A capture folder is read from its layout/*.json; a mock's output folder
from its *_layout.json. Findings are warnings and exit 0; --strict exits 1 when there are any.
Exit 2 is a usage error (no layout found).

diff compares a capture folder (a path, or a name under data/visual/) with the golden set
data/visual/golden/NAME/, shot by shot, with the tolerances in harness/config/visual.toml (hx/golden.py).
Over-tolerance and size-mismatch shots fail (exit 1); diff PNGs go to data/visual/diff/NAME/<capture>/.
--accept replaces the golden set with the capture and exits 0.

--metric exact (the default) compares pixels: a pixel changes above max_channel_delta, a shot is over above
max_changed_share of its pixels. --metric ssim (sw-tho3.14) blurs both captures and compares SSIM over
16 px tiles, which ignores anti-aliasing and dither noise; thresholds in [golden.perceptual]. Calibration
table: the sw-tho3.14 bead notes.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from hx import golden, visual
from hx.output import FAIL, OK, WARN, Check, Result
from hx.paths import repo_root

HELP = "Visual assessment of battles: lint a capture's layout for overlapping labels and low contrast (no model)"


def add_args(p) -> None:
    sub = p.add_subparsers(dest="action", required=True, metavar="<action>")
    ln = sub.add_parser("lint", help="model-free layout checks on a capture or a layout JSON")
    ln.add_argument("path", help="a layout JSON, a capture folder, or a mock output folder")
    ln.add_argument("--png", help="the image to sample for contrast (default: the layout's own image)")
    ln.add_argument("--strict", action="store_true", help="exit 1 when any layout has findings")
    df = sub.add_parser("diff", help="golden-image diff of a capture against data/visual/golden/NAME")
    df.add_argument("capture", help="a capture folder, or a name under data/visual/")
    df.add_argument("--golden", required=True, metavar="NAME", help="the golden set under data/visual/golden/")
    df.add_argument("--accept", action="store_true",
                    help="replace the golden set with this capture (exit 0); the diff is not run")
    df.add_argument("--metric", choices=("exact", "ssim"), default="exact",
                    help="exact pixels (default) or the blurred SSIM over tiles (perceptual, sw-tho3.14)")
    # also accepted after the action, as hx godot does
    for sp in (ln, df):
        sp.add_argument("--json", action="store_true", default=argparse.SUPPRESS)
        sp.add_argument("-v", "--verbose", action="store_true", default=argparse.SUPPRESS)


def run(args) -> Result:
    if getattr(args, "action", "lint") == "diff":
        return run_diff(args)
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


def run_diff(args) -> Result:
    r = Result("visual")
    data_visual = repo_root() / "data" / "visual"
    capture = Path(args.capture)
    if not capture.is_dir():
        capture = data_visual / args.capture
    name = args.golden
    if not capture.is_dir() or not name or name in (".", "..") or any(c in name for c in "/\\"):
        r.checks.append(Check("capture", FAIL, f"no capture folder {args.capture!r} (or a bad --golden name {name!r})"))
        r.exit_override = 2
        return r
    gold = data_visual / "golden" / name
    if args.accept:
        if gold.resolve() == capture.resolve() or gold.resolve() in capture.resolve().parents:
            r.checks.append(Check("accept", FAIL, "the capture is inside its own golden set; refusing to replace it"))
            r.exit_override = 2
            return r
        n = golden.accept(capture, gold)
        r.data = {"golden": str(gold), "files": n}
        r.checks.append(Check("accept", OK, f"{n} file(s) from {capture} into {gold}"))
        return r
    if not gold.is_dir():
        r.checks.append(Check("golden", FAIL, f"no golden set {gold}; run again with --accept to create it"))
        r.exit_override = 2
        return r
    tol = golden.load_tolerance()
    perc = golden.load_perceptual() if args.metric == "ssim" else None
    out = data_visual / "diff" / name / capture.name
    shots = golden.diff_capture(capture, gold, out, tol, perc)
    counts = {s: sum(1 for x in shots if x.status == s) for s in ("same", "within", "over", "mismatch", "new", "missing")}
    if perc is None:
        tolerance = f"{tol.max_channel_delta} channel, {tol.max_changed_share:.2%} of pixels"
    else:
        tolerance = (f"SSIM {perc.min_block_ssim:g} per {perc.block}px tile after blur {perc.blur_radius}, "
                     f"{perc.max_changed_share:.2%} of tiles")
    r.data = {"metric": args.metric, "shots": len(shots), **counts, "tolerance": tolerance}
    if not shots:
        r.checks.append(Check("shots", WARN, f"no PNGs under {capture}"))
    for s in shots:
        if s.status == "same" or s.status == "within":
            r.checks.append(Check(f"{s.name}: {s.status}", OK, s.detail or "identical"))
        elif s.status in ("over", "mismatch"):
            where = f" diff {s.diff_png}" if s.diff_png else ""
            r.checks.append(Check(f"{s.name}: over tolerance", FAIL, f"{s.detail}{where}"))
        else:
            r.checks.append(Check(f"{s.name}: {s.status}", WARN, s.detail))
    r.exit_override = 1 if any(s.failed for s in shots) else 0
    return r
