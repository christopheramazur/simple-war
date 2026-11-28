"""Golden-image diff for battle captures (U1 B13a, sw-tho3.13; draft 02 §5.6 V12).

A capture folder (data/visual/<capture>/, written by the capture runner) is compared shot by shot with a
local baseline in data/visual/golden/<NAME>/. The diff is exact per pixel with a numeric tolerance, in
harness/config/visual.toml [golden]:

  max_channel_delta   a pixel is changed when its largest channel difference (0-255, all channels) exceeds this
  max_changed_share   a shot is over tolerance when more than this share of its pixels is changed

Statuses per shot: same (no pixel differs at all), within (some pixels changed, share at or under the limit),
over (share above the limit), mismatch (image size or channel count differs; a failure), new (capture has a
shot the golden set lacks; advisory) and missing (the golden set has a shot the capture did not produce;
advisory, a partial capture is normal). No model and no new dependency: PNGs are read by hx.visual's
stdlib decoder and diff images are written here.

Golden sets are per machine (AGENTS.md; U1 OQ5), so they stay out of git with the rest of data/visual/.
"""

from __future__ import annotations

import shutil
import struct
import tomllib
import zlib
from dataclasses import dataclass
from pathlib import Path

from hx import visual
from hx.paths import HARNESS_ROOT

CONFIG = HARNESS_ROOT / "config" / "visual.toml"
MAGENTA = (255, 0, 255)  # changed pixels in a diff image


@dataclass(frozen=True)
class Tolerance:
    max_channel_delta: int
    max_changed_share: float


@dataclass(frozen=True)
class ShotDiff:
    name: str  # path relative to the capture folder, posix separators
    status: str  # same | within | over | mismatch | new | missing
    changed: int = 0
    total: int = 0
    max_delta: int = 0
    detail: str = ""
    diff_png: Path | None = None

    @property
    def share(self) -> float:
        return self.changed / self.total if self.total else 0.0

    @property
    def failed(self) -> bool:
        return self.status in ("over", "mismatch")


def load_tolerance(path: Path = CONFIG) -> Tolerance:
    cfg = tomllib.loads(path.read_text(encoding="utf-8")).get("golden", {})
    return Tolerance(int(cfg.get("max_channel_delta", 8)), float(cfg.get("max_changed_share", 0.01)))


# ---- pixels -----------------------------------------------------------------

def pixel_deltas(a: bytes, b: bytes, channels: int) -> list[int]:
    """The largest channel difference of each pixel (0..255). a and b are unfiltered 8-bit rows of equal length."""
    d = [abs(x - y) for x, y in zip(a, b)]
    if channels == 1:
        return d
    return [max(d[i:i + channels]) for i in range(0, len(d), channels)]


def write_rgb_png(path: Path, width: int, height: int, rgb: bytes) -> None:
    """An 8-bit RGB, non-interlaced PNG (filter 0 on every row)."""
    stride = width * 3
    raw = b"".join(b"\x00" + rgb[y * stride:(y + 1) * stride] for y in range(height))

    def chunk(kind: bytes, body: bytes) -> bytes:
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    data = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_bytes(data)


def _diff_image(shot: visual.Pixels, deltas: list[int], tol: int) -> bytes:
    """Changed pixels in magenta; the rest of the capture, dimmed, so the change has its context."""
    ch = shot.channels
    out = bytearray()
    for p, d in enumerate(deltas):
        if d > tol:
            out += bytes(MAGENTA)
            continue
        i = p * ch
        if ch < 3:
            r = g = b = shot.data[i]
        else:
            r, g, b = shot.data[i], shot.data[i + 1], shot.data[i + 2]
        out += bytes((r // 2, g // 2, b // 2))
    return bytes(out)


# ---- folders ----------------------------------------------------------------

def _pngs(root: Path) -> dict[str, Path]:
    return {p.relative_to(root).as_posix(): p for p in sorted(root.rglob("*.png")) if p.is_file()}


def compare_shot(name: str, golden: Path, shot: Path, tol: Tolerance, diff_png: Path | None = None) -> ShotDiff:
    g = visual.read_png(golden)
    s = visual.read_png(shot)
    if (g.width, g.height) != (s.width, s.height) or g.channels != s.channels:
        return ShotDiff(name, "mismatch", detail=f"{s.width}x{s.height}/{s.channels}ch vs golden "
                                                   f"{g.width}x{g.height}/{g.channels}ch")
    total = g.width * g.height
    deltas = pixel_deltas(g.data, s.data, g.channels)
    changed = sum(1 for d in deltas if d > tol.max_channel_delta)
    max_delta = max(deltas) if deltas else 0
    if changed == 0:
        return ShotDiff(name, "same", 0, total, max_delta)
    share = changed / total
    status = "over" if share > tol.max_changed_share else "within"
    written = None
    if diff_png is not None:
        write_rgb_png(diff_png, s.width, s.height, _diff_image(s, deltas, tol.max_channel_delta))
        written = diff_png
    detail = f"{share:.2%} of pixels changed (limit {tol.max_changed_share:.2%}), max channel delta {max_delta}"
    return ShotDiff(name, status, changed, total, max_delta, detail, written)


def diff_capture(capture: Path, golden: Path, out: Path | None, tol: Tolerance) -> list[ShotDiff]:
    """Every PNG in the capture against the golden set, by relative path. `out` receives diff PNGs for changed shots."""
    cap, gold = _pngs(capture), _pngs(golden)
    results: list[ShotDiff] = []
    for name in sorted(set(cap) | set(gold)):
        if name not in gold:
            results.append(ShotDiff(name, "new", detail="no golden image yet (--accept adds it)"))
        elif name not in cap:
            results.append(ShotDiff(name, "missing", detail="the capture did not produce this shot"))
        else:
            dest = out / name if out is not None else None
            results.append(compare_shot(name, gold[name], cap[name], tol, dest))
    return results


def accept(capture: Path, golden: Path) -> int:
    """Replace the golden set NAME with the capture's files (PNG and JSON). Returns the number of files copied."""
    if golden.exists():
        shutil.rmtree(golden)
    n = 0
    for src in sorted(capture.rglob("*")):
        if src.is_file() and src.suffix.lower() in (".png", ".json"):
            dst = golden / src.relative_to(capture)
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, dst)
            n += 1
    return n
