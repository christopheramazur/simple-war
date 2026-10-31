"""Scan files git would commit for credentials (DESIGN.md §4: keys never in repo)."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

from hx.proc import run as sh

# Provider key shapes. Kept specific to avoid noise in 6k+ skill files.
PATTERNS: dict[str, re.Pattern[str]] = {
    "anthropic": re.compile(r"sk-ant-[A-Za-z0-9_\-]{20,}"),
    "openrouter": re.compile(r"sk-or-v1-[A-Za-z0-9]{32,}"),
    "openai": re.compile(r"sk-(?:proj-)?[A-Za-z0-9]{32,}"),
    "google": re.compile(r"AIza[0-9A-Za-z_\-]{35}"),
    "groq": re.compile(r"gsk_[A-Za-z0-9]{40,}"),
    "github": re.compile(r"gh[pousr]_[A-Za-z0-9]{36,}"),
    "huggingface": re.compile(r"hf_[A-Za-z0-9]{30,}"),
    "private-key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"),
}
# One combined pattern lets most files be rejected in a single pass.
_ANY = re.compile("|".join(f"(?:{p.pattern})" for p in PATTERNS.values()))
MAX_BYTES = 1_000_000
ALLOW_MARKER = "hx-allow-secret"  # put on a line to mark a known fake


@dataclass
class Finding:
    path: str
    line: int
    kind: str


def candidate_files(root: Path) -> list[str]:
    """Tracked + untracked-but-not-ignored files: what a commit could include."""
    r = sh(["git", "ls-files", "-co", "--exclude-standard", "-z"], cwd=root, timeout=60)
    return [f for f in r.out.split("\0") if f] if r.ok else []


def scan_text(text: str) -> list[tuple[int, str]]:
    if not _ANY.search(text):
        return []
    hits = []
    for n, line in enumerate(text.splitlines(), 1):
        if ALLOW_MARKER in line:
            continue
        for kind, pat in PATTERNS.items():
            if pat.search(line):
                hits.append((n, kind))
    return hits


def scan(root: Path, files: list[str] | None = None) -> list[Finding]:
    findings = []
    for rel in files if files is not None else candidate_files(root):
        p = root / rel
        try:
            if p.stat().st_size > MAX_BYTES:
                continue
            raw = p.read_bytes()
        except OSError:
            continue
        if b"\0" in raw[:4096]:  # binary
            continue
        for n, kind in scan_text(raw.decode("utf-8", errors="replace")):
            findings.append(Finding(rel, n, kind))
    return findings
