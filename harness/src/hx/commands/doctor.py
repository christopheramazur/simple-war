"""hx doctor: verify the harness toolchain and guard rails. Exit 1 on any FAIL."""

from __future__ import annotations

import sys

from hx import godot, keystore, secrets_scan
from hx.output import FAIL, OK, WARN, Check, Result
from hx.paths import HARNESS_ROOT, repo_root
from hx.proc import run as sh

HELP = "Check toolchain, ignore rules and scan for committed secrets"

# (command, required?) — optional tools only WARN; they arrive with later issues.
TOOLS = [
    (["git", "--version"], True),
    (["uv", "--version"], True),
    (["bd", "--version"], True),
    (["rtk", "--version"], False),
]


def add_args(p) -> None:
    p.add_argument("--no-secrets", action="store_true", help="skip the secret scan")


def run(args) -> Result:
    root = repo_root()
    r = Result("doctor")
    r.data["python"] = sys.version.split()[0]
    r.data["repo"] = str(root)

    for cmd, required in TOOLS:
        res = sh(cmd, cwd=root)
        if res.ok:
            r.checks.append(Check(cmd[0], OK, res.out.splitlines()[0] if res.out else ""))
        else:
            r.checks.append(Check(cmd[0], FAIL if required else WARN, res.err or "failed"))

    bins = godot.binaries(root)
    for kind in ("editor", "console"):
        p = bins.get(kind)
        r.checks.append(Check(f"godot {kind}", OK if p else WARN, p.name if p else "not found at repo root"))

    # Relative to the harness itself, so this still holds once it is extracted.
    ign = sh(["git", "check-ignore", "-q", "data/ledger.duckdb"], cwd=HARNESS_ROOT)
    r.checks.append(Check("harness/data ignored", OK if ign.ok else FAIL,
                          "" if ign.ok else "harness/data/ would be committed"))

    kr = keystore.keyring_backend()
    r.checks.append(Check("keyring", OK if kr != "unavailable" else WARN,
                          kr if kr != "unavailable" else "no OS keyring; hx secrets set --file falls back to ~/.hx"))

    if not args.no_secrets:
        files = secrets_scan.candidate_files(root)
        found = secrets_scan.scan(root, files)
        r.data["scanned_files"] = len(files)
        if found:
            detail = "; ".join(f"{f.path}:{f.line} ({f.kind})" for f in found[:10])
            r.checks.append(Check("secrets", FAIL, f"{len(found)} hit(s): {detail}"))
        else:
            r.checks.append(Check("secrets", OK, "none found"))
    return r
