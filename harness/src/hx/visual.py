"""Model-free layout checks for battle captures (U1 B12, sw-tho3.12; draft 02 §5.6 V11).

Input is a layout JSON written by the game: the label and footprint rectangles ContextView
drew, in image pixels (src/presentation/capture/capture_runner.gd writes layout/<shot>_<kind>.json,
src/presentation/mocks/mock_runner.gd writes <name>_layout.json for a battle mock). The image is the
PNG those rectangles were drawn into. Checks, per frame:

  label_overlap        two labels of different squads overlap by more than MIN_LABEL_OVERLAP of the smaller
  label_on_footprint   a label covers more than MIN_LABEL_ON_FOOTPRINT of another squad's footprint
  footprint_overlap    two squads' footprints overlap by more than MIN_FOOTPRINT_OVERLAP of the smaller
  label_contrast       a label's text, over the ground under it, is below CONTRAST_MIN (WCAG 2.x ratio)

Nothing here needs a model. The findings are advisory (warnings): a clarity check is evidence to
read, like a judge's answer (draft 02 §5.6 "Trust"), and never gates a merge by itself.

Luminance: the WCAG relative luminance of linear RGB with the Rec. 709 weights 0.2126 / 0.7152 /
0.0722, the same weights as CvdSim.simulate's greyscale variant (src/presentation/mocks/cvd_sim.gd).
sRGB is linearised with the sRGB transfer curve (threshold 0.04045, as Godot's Color.srgb_to_linear).
A label's text colour is blended over its ground as the GPU blends it, in sRGB: fg.a * fg + (1 - fg.a) * ground.
The ground under a label is the most common colour (channels quantised to 16 levels) of the image
inside the label's rectangle, averaged over the pixels of that bucket. The label's own text is a
minority of the pixels, so it does not win the vote on ordinary labels.

PNG decoding is stdlib only (zlib): 8-bit greyscale, grey+alpha, RGB and RGBA, non-interlaced, which
is what Godot's save_png writes.
"""

from __future__ import annotations

import json
import math
import struct
import zlib
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

LUMA = (0.2126, 0.7152, 0.0722)  # cvd_sim.gd greyscale weights (linear RGB)
CONTRAST_MIN = 4.5  # WCAG 2.x AA for normal text; labels are 11 px
MIN_LABEL_OVERLAP = 0.10  # share of the smaller label's area
MIN_LABEL_ON_FOOTPRINT = 0.10  # share of the label's area
MIN_FOOTPRINT_OVERLAP = 0.25  # share of the smaller footprint's area
QUANT_SHIFT = 4  # 8-bit channels quantised to 16 levels for the ground vote

_CHANNELS = {0: 1, 2: 3, 4: 2, 6: 4}  # PNG colour type -> channels (8-bit only)
_PNG_SIG = b"\x89PNG\r\n\x1a\n"


@dataclass(frozen=True)
class Box:
    kind: str  # "label" | "footprint"
    squad: int
    player: int
    frame: int
    x: float
    y: float
    w: float
    h: float
    fg: tuple[float, float, float, float] | None = None  # labels: text colour, alpha included

    @property
    def area(self) -> float:
        return max(self.w, 0.0) * max(self.h, 0.0)

    def intersection(self, other: Box) -> float:
        iw = min(self.x + self.w, other.x + other.w) - max(self.x, other.x)
        ih = min(self.y + self.h, other.y + other.h) - max(self.y, other.y)
        return max(iw, 0.0) * max(ih, 0.0)

    def where(self) -> str:
        return f"[{self.x:.0f},{self.y:.0f} {self.w:.0f}x{self.h:.0f}]"


@dataclass(frozen=True)
class Finding:
    check: str
    frame: int
    squads: tuple[int, ...]
    detail: str
    rect: str = ""


# ---- colour -----------------------------------------------------------------

def _linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def luminance(rgb: tuple[float, float, float]) -> float:
    """WCAG relative luminance of an sRGB colour with channels in 0..1."""
    r, g, b = (_linear(c) for c in rgb)
    return LUMA[0] * r + LUMA[1] * g + LUMA[2] * b


def contrast_ratio(a: tuple[float, float, float], b: tuple[float, float, float]) -> float:
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def blend(fg: tuple[float, float, float, float], ground: tuple[float, float, float]) -> tuple[float, float, float]:
    a = fg[3]
    return tuple(a * fg[i] + (1.0 - a) * ground[i] for i in range(3))  # type: ignore[return-value]


# ---- PNG --------------------------------------------------------------------

@dataclass(frozen=True)
class Pixels:
    width: int
    height: int
    channels: int
    data: bytes  # raw unfiltered rows, 8-bit

    def ground(self, x: float, y: float, w: float, h: float) -> tuple[float, float, float] | None:
        """The most common colour (quantised vote) inside a rectangle of pixels, 0..1 per channel."""
        x0, y0 = max(math.floor(x), 0), max(math.floor(y), 0)
        x1, y1 = min(math.ceil(x + w), self.width), min(math.ceil(y + h), self.height)
        if x1 <= x0 or y1 <= y0:
            return None
        votes: Counter[tuple[int, int, int]] = Counter()
        sums: dict[tuple[int, int, int], list[int]] = {}
        ch = self.channels
        for py in range(y0, y1):
            row = py * self.width * ch
            for px in range(x0, x1):
                i = row + px * ch
                if ch < 3:  # greyscale (and grey + alpha)
                    r = g = b = self.data[i]
                else:
                    r, g, b = self.data[i], self.data[i + 1], self.data[i + 2]
                key = (r >> QUANT_SHIFT, g >> QUANT_SHIFT, b >> QUANT_SHIFT)
                votes[key] += 1
                s = sums.setdefault(key, [0, 0, 0])
                s[0] += r
                s[1] += g
                s[2] += b
        key, n = votes.most_common(1)[0]
        s = sums[key]
        return (s[0] / n / 255.0, s[1] / n / 255.0, s[2] / n / 255.0)


def read_png(path: Path) -> Pixels:
    raw = Path(path).read_bytes()
    if not raw.startswith(_PNG_SIG):
        raise ValueError(f"not a PNG: {path}")
    pos = len(_PNG_SIG)
    idat: list[bytes] = []
    width = height = colour = 0
    while pos + 8 <= len(raw):
        length, kind = struct.unpack(">I4s", raw[pos:pos + 8])
        body = raw[pos + 8:pos + 8 + length]
        pos += 12 + length  # length, type, data, CRC
        if kind == b"IHDR":
            width, height, depth, colour, _comp, _flt, interlace = struct.unpack(">IIBBBBB", body)
            if depth != 8 or colour not in _CHANNELS or interlace != 0:
                raise ValueError(f"unsupported PNG (depth {depth}, colour {colour}, interlace {interlace}): {path}")
        elif kind == b"IDAT":
            idat.append(body)
        elif kind == b"IEND":
            break
    if width == 0 or height == 0:
        raise ValueError(f"PNG without IHDR: {path}")
    ch = _CHANNELS[colour]
    return Pixels(width, height, ch, _unfilter(zlib.decompress(b"".join(idat)), width * ch, height, ch))


def _unfilter(raw: bytes, stride: int, height: int, bpp: int) -> bytes:
    out = bytearray(stride * height)
    prev = bytearray(stride)
    pos = 0
    for y in range(height):
        ft = raw[pos]
        line = bytearray(raw[pos + 1:pos + 1 + stride])
        pos += 1 + stride
        if ft == 1:  # Sub
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 0xFF
        elif ft == 2:  # Up
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ft == 3:  # Average
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif ft == 4:  # Paeth
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF
        elif ft != 0:
            raise ValueError(f"bad PNG filter type {ft}")
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return bytes(out)


# ---- layout -----------------------------------------------------------------

def load_layout(path: Path) -> tuple[dict, list[Box]]:
    """The layout JSON's header and its boxes (rect is [x, y, w, h] in image pixels)."""
    doc = json.loads(Path(path).read_text(encoding="utf-8"))
    boxes = []
    for r in doc.get("rects", []):
        x, y, w, h = (float(v) for v in r["rect"])
        fg = tuple(float(v) for v in r["fg"]) if r.get("fg") else None
        boxes.append(Box(str(r["kind"]), int(r["squad"]), int(r.get("player", 0)), int(r.get("frame", 0)),
                         x, y, w, h, fg))  # type: ignore[arg-type]
    return doc, boxes


def resolve_image(layout_path: Path, image: str) -> Path | None:
    """A capture keeps layouts in layout/ and PNGs in the capture folder; a mock keeps both together."""
    for cand in (layout_path.parent / image, layout_path.parent.parent / image):
        if cand.is_file():
            return cand
    return None


# ---- checks -----------------------------------------------------------------

def _pair_findings(boxes: list[Box], frame: int) -> list[Finding]:
    out: list[Finding] = []
    labels = [b for b in boxes if b.kind == "label"]
    feet = [b for b in boxes if b.kind == "footprint"]
    for i, a in enumerate(labels):
        for b in labels[i + 1:]:
            if a.squad == b.squad:
                continue
            shared = a.intersection(b)
            share = shared / min(a.area, b.area) if min(a.area, b.area) > 0 else 0.0
            if share > MIN_LABEL_OVERLAP:
                out.append(Finding("label_overlap", frame, (a.squad, b.squad),
                                   f"labels overlap {share:.0%} of the smaller", a.where()))
    for lab in labels:
        for ft in feet:
            if ft.squad == lab.squad or lab.area <= 0:
                continue
            share = lab.intersection(ft) / lab.area
            if share > MIN_LABEL_ON_FOOTPRINT:
                out.append(Finding("label_on_footprint", frame, (lab.squad, ft.squad),
                                   f"label covers {share:.0%} of squad {ft.squad}'s footprint", lab.where()))
    for i, a in enumerate(feet):
        for b in feet[i + 1:]:
            if a.squad == b.squad:
                continue
            small = min(a.area, b.area)
            if small <= 0:
                continue
            share = a.intersection(b) / small
            if share > MIN_FOOTPRINT_OVERLAP:
                out.append(Finding("footprint_overlap", frame, (a.squad, b.squad),
                                   f"footprints overlap {share:.0%} of the smaller", a.where()))
    return out


def lint(boxes: list[Box], pixels: Pixels | None) -> tuple[list[Finding], bool]:
    """All findings, and whether the contrast check ran (it needs the image)."""
    findings: list[Finding] = []
    for frame in sorted({b.frame for b in boxes}):
        fb = [b for b in boxes if b.frame == frame]
        findings += _pair_findings(fb, frame)
    if pixels is None:
        return findings, False
    for b in boxes:
        if b.kind != "label" or b.fg is None:
            continue
        ground = pixels.ground(b.x, b.y, b.w, b.h)
        if ground is None:
            continue
        ratio = contrast_ratio(blend(b.fg, ground), ground)
        if ratio < CONTRAST_MIN:
            findings.append(Finding("label_contrast", b.frame, (b.squad,),
                                    f"text contrast {ratio:.2f}:1 on its ground (AA needs {CONTRAST_MIN}:1)", b.where()))
    return findings, True


def lint_file(layout_path: Path, png: Path | None = None) -> dict:
    """Lint one layout file. Returns {layout, image, contrast, findings: [dict]} (findings sorted by frame)."""
    doc, boxes = load_layout(layout_path)
    image = png or (resolve_image(layout_path, str(doc.get("image", ""))) if doc.get("image") else None)
    pixels = read_png(image) if image is not None else None
    findings, contrast = lint(boxes, pixels)
    findings.sort(key=lambda f: (f.frame, f.check, f.squads))
    return {"layout": str(layout_path), "image": str(image) if image else None, "contrast": contrast,
            "boxes": len(boxes),
            "findings": [{"check": f.check, "frame": f.frame, "squads": list(f.squads), "detail": f.detail,
                          "rect": f.rect} for f in findings]}


def layout_files(path: Path) -> list[Path]:
    """A layout file, a capture folder (layout/*.json) or a mock's output folder (*_layout.json)."""
    if path.is_file():
        return [path]
    found = sorted((path / "layout").glob("*.json")) if (path / "layout").is_dir() else []
    return found or sorted(path.glob("*_layout.json"))
