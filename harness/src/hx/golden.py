"""Golden-image diff for battle captures (U1 B13a, sw-tho3.13; draft 02 §5.6 V12).

A capture folder (data/visual/<capture>/, written by the capture runner) is compared shot by shot with a
local baseline in data/visual/golden/<NAME>/. The diff is exact per pixel with a numeric tolerance, in
harness/config/visual.toml [golden]:

  max_channel_delta   a pixel is changed when its largest channel difference (0-255, all channels) exceeds this
  max_changed_share   a shot is over tolerance when more than this share of its pixels is changed

Statuses per shot: same (nothing changed beyond the tolerance; identical captures diff to zero), within (some
pixels or tiles changed, share at or under the limit),
over (share above the limit), mismatch (image size or channel count differs; a failure), new (capture has a
shot the golden set lacks; advisory) and missing (the golden set has a shot the capture did not produce;
advisory, a partial capture is normal). No model and no new dependency: PNGs are read by hx.visual's
stdlib decoder and diff images are written here.

A perceptual mode (sw-tho3.14, --metric ssim) compares blocks instead of pixels: the capture is split into
block x block tiles (harness/config/visual.toml [golden.perceptual]), each tile's SSIM (Wang et al. 2004, on
each colour channel, the lowest of the three kept) is computed, and a tile is changed when its SSIM is below
min_block_ssim. A shot is over when the changed share of tiles exceeds max_changed_share. Anti-aliasing and
rounding noise leaves the structure of a tile intact, so its SSIM stays near 1; a moved label or a
recoloured block does not. Stdlib only, as the exact mode.

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
class Perceptual:
    block: int  # tile edge in pixels
    min_block_ssim: float  # a tile below this SSIM is changed
    max_changed_share: float  # a shot is over when more than this share of its tiles is changed
    blur_radius: int = 1  # box blur (window 2r+1) on both captures before the SSIM; absorbs AA and dither


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


def load_perceptual(path: Path = CONFIG) -> Perceptual:
    cfg = tomllib.loads(path.read_text(encoding="utf-8")).get("golden", {}).get("perceptual", {})
    return Perceptual(int(cfg.get("block", 16)), float(cfg.get("min_block_ssim", 0.9)),
                      float(cfg.get("max_changed_share", 0.001)), int(cfg.get("blur_radius", 1)))


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


def _diff_image(shot: visual.Pixels, changed: list[bool]) -> bytes:
    """Changed pixels in magenta; the rest of the capture, dimmed, so the change has its context."""
    ch = shot.channels
    out = bytearray()
    for p, c in enumerate(changed):
        if c:
            out += bytes(MAGENTA)
            continue
        i = p * ch
        if ch < 3:
            r = g = b = shot.data[i]
        else:
            r, g, b = shot.data[i], shot.data[i + 1], shot.data[i + 2]
        out += bytes((r // 2, g // 2, b // 2))
    return bytes(out)


# ---- perceptual (SSIM over tiles) -------------------------------------------

SSIM_C1 = (0.01 * 255) ** 2
SSIM_C2 = (0.03 * 255) ** 2


def tile_ssim(x: list[int], y: list[int], w: int, h: int, block: int) -> list[float]:
    """SSIM of each block x block tile (row-major tiles; edge tiles are smaller) of one 8-bit channel."""
    out: list[float] = []
    for by in range(0, h, block):
        rows = range(by, min(by + block, h))
        for bx in range(0, w, block):
            ex = min(bx + block, w)
            xs: list[int] = []
            ys: list[int] = []
            for r in rows:
                o = r * w
                xs.extend(x[o + bx:o + ex])
                ys.extend(y[o + bx:o + ex])
            n = len(xs)
            mx, my = sum(xs) / n, sum(ys) / n
            vx = max(sum(v * v for v in xs) / n - mx * mx, 0.0)
            vy = max(sum(v * v for v in ys) / n - my * my, 0.0)
            cxy = sum(a * b for a, b in zip(xs, ys)) / n - mx * my
            out.append(((2 * mx * my + SSIM_C1) * (2 * cxy + SSIM_C2))
                       / ((mx * mx + my * my + SSIM_C1) * (vx + vy + SSIM_C2)))
    return out


def _planes(p: visual.Pixels) -> list[list[int]]:
    """The colour planes to compare: grey (one plane, grey+alpha too) or R, G, B (alpha is not compared)."""
    if p.channels < 3:
        return [list(p.data[0::p.channels])]
    return [list(p.data[c::p.channels]) for c in range(3)]


def box_blur(plane: list[int], w: int, h: int, radius: int) -> list[int]:
    """Separable box blur of one plane (window 2r+1, edges clamped, rounded). radius 0 returns the plane.
    Row and column sums are taken with zip over shifted slices, so the loops stay in C."""
    if radius <= 0:
        return plane
    n = 2 * radius + 1
    half = n * n // 2

    def window_sums(seq: list[int]) -> list[int]:
        padded = [seq[0]] * radius + seq + [seq[-1]] * radius
        return [sum(t) for t in zip(*(padded[k:k + len(seq)] for k in range(n)))]

    rows = [window_sums(plane[y * w:(y + 1) * w]) for y in range(h)]  # horizontal sums per row
    out: list[int] = []
    for y in range(h):
        ys = [min(max(y + k, 0), h - 1) for k in range(-radius, radius + 1)]
        col = [sum(t) for t in zip(*(rows[i] for i in ys))]
        out.extend((v + half) // (n * n) for v in col)
    return out


def tile_changed(a: visual.Pixels, b: visual.Pixels, perc: Perceptual) -> tuple[list[float], list[bool]]:
    """Per tile, the lowest SSIM over the colour planes after the blur, and whether it is changed (below min_block_ssim)."""
    pa = [box_blur(v, a.width, a.height, perc.blur_radius) for v in _planes(a)]
    pb = [box_blur(v, b.width, b.height, perc.blur_radius) for v in _planes(b)]
    per = [tile_ssim(x, y, a.width, a.height, perc.block) for x, y in zip(pa, pb)]
    scores = [min(vals) for vals in zip(*per)]
    return scores, [sc < perc.min_block_ssim for sc in scores]


def _pixel_mask_from_tiles(width: int, height: int, block: int, flags: list[bool]) -> list[bool]:
    tiles_x = -(-width // block)
    return [flags[(y // block) * tiles_x + x // block] for y in range(height) for x in range(width)]


# ---- folders ----------------------------------------------------------------

def _pngs(root: Path) -> dict[str, Path]:
    return {p.relative_to(root).as_posix(): p for p in sorted(root.rglob("*.png")) if p.is_file()}


def compare_shot(name: str, golden: Path, shot: Path, tol: Tolerance, diff_png: Path | None = None,
                 perc: Perceptual | None = None) -> ShotDiff:
    g = visual.read_png(golden)
    s = visual.read_png(shot)
    if (g.width, g.height) != (s.width, s.height) or g.channels != s.channels:
        return ShotDiff(name, "mismatch", detail=f"{s.width}x{s.height}/{s.channels}ch vs golden "
                                                   f"{g.width}x{g.height}/{g.channels}ch")
    total = g.width * g.height
    deltas = pixel_deltas(g.data, s.data, g.channels)
    max_delta = max(deltas) if deltas else 0
    if max_delta == 0:
        return ShotDiff(name, "same", 0, total, 0)
    if perc is None:
        mask = [d > tol.max_channel_delta for d in deltas]
        changed, denom = sum(mask), total
        share = changed / denom
        limit = tol.max_changed_share
        detail = f"{share:.2%} of pixels changed (limit {limit:.2%}), max channel delta {max_delta}"
    else:
        scores, flags = tile_changed(g, s, perc)
        mask = _pixel_mask_from_tiles(s.width, s.height, perc.block, flags)
        changed, denom = sum(flags), len(flags)
        share = changed / denom
        limit = perc.max_changed_share
        detail = (f"{share:.2%} of {perc.block}px tiles below SSIM {perc.min_block_ssim:g} (limit {limit:.2%}), "
                  f"lowest tile SSIM {min(scores):.3f}, max channel delta {max_delta}")
    if changed == 0:  # nothing beyond the tolerance (exact mode: jitter inside max_channel_delta)
        return ShotDiff(name, "same", 0, denom, max_delta, detail)
    status = "over" if share > limit else "within"
    written = None
    if diff_png is not None:
        write_rgb_png(diff_png, s.width, s.height, _diff_image(s, mask))
        written = diff_png
    return ShotDiff(name, status, changed, denom, max_delta, detail, written)


def diff_capture(capture: Path, golden: Path, out: Path | None, tol: Tolerance,
                 perc: Perceptual | None = None) -> list[ShotDiff]:
    """Every PNG in the capture against the golden set, by relative path. `out` receives diff PNGs for changed shots.
    `perc` switches the comparison from exact pixels to SSIM tiles (sw-tho3.14)."""
    cap, gold = _pngs(capture), _pngs(golden)
    results: list[ShotDiff] = []
    for name in sorted(set(cap) | set(gold)):
        if name not in gold:
            results.append(ShotDiff(name, "new", detail="no golden image yet (--accept adds it)"))
        elif name not in cap:
            results.append(ShotDiff(name, "missing", detail="the capture did not produce this shot"))
        else:
            dest = out / name if out is not None else None
            results.append(compare_shot(name, gold[name], cap[name], tol, dest, perc))
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
