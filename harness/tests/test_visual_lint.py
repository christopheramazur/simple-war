"""hx visual lint (sw-tho3.12, U1 B12): layout checks on constructed captures, no model."""

from __future__ import annotations

import json
import struct
import zlib

import pytest

from hx import visual
from hx.commands import visual as visual_cmd
from hx.output import FAIL
from hx.visual import Box, Pixels


def _chunk(kind: bytes, body: bytes) -> bytes:
    return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    return a if pa <= pb and pa <= pc else (b if pb <= pc else c)


def _filter_row(row: bytes, prev: bytes, bpp: int, ft: int) -> bytes:
    out = bytearray()
    for i, x in enumerate(row):
        a = row[i - bpp] if i >= bpp else 0
        b = prev[i]
        c = prev[i - bpp] if i >= bpp else 0
        pred = {0: 0, 1: a, 2: b, 3: (a + b) >> 1, 4: _paeth(a, b, c)}[ft]
        out.append((x - pred) & 0xFF)
    return bytes(out)


def write_png(path, width, height, pixel, channels=4, filters=(0, 1, 2, 3, 4)) -> None:
    """A PNG like Godot's save_png (8-bit, non-interlaced); `pixel(x, y)` gives a tuple of channels."""
    colour = {1: 0, 2: 4, 3: 2, 4: 6}[channels]
    raw = bytearray()
    prev = bytes(width * channels)
    for y in range(height):
        row = bytearray()
        for x in range(width):
            row += bytes(pixel(x, y))
        ft = filters[y % len(filters)]
        raw.append(ft)
        raw += _filter_row(bytes(row), prev, channels, ft)
        prev = bytes(row)
    ihdr = struct.pack(">IIBBBBB", width, height, 8, colour, 0, 0, 0)
    data = b"\x89PNG\r\n\x1a\n" + _chunk(b"IHDR", ihdr) + _chunk(b"IDAT", zlib.compress(bytes(raw))) + _chunk(b"IEND", b"")
    path.write_bytes(data)


def _label(squad, x, y, w, h, fg=(0.87, 0.89, 0.92, 1.0), frame=0):
    return {"kind": "label", "squad": squad, "player": 1, "frame": frame, "rect": [x, y, w, h], "fg": list(fg)}


def _layout(path, image, rects, size=(200, 120)):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"image": image, "size": list(size), "rects": rects}), encoding="utf-8")


def _checks(result: dict) -> list[str]:
    return [f["check"] for f in result["findings"]]


def test_luminance_and_ratio_match_wcag_reference_values():
    assert visual.contrast_ratio((1, 1, 1), (0, 0, 0)) == pytest.approx(21.0)
    assert visual.contrast_ratio((0.5, 0.5, 0.5), (0.5, 0.5, 0.5)) == pytest.approx(1.0)
    # #777777 on white is 4.48:1 in WCAG 2.x (just under AA for normal text)
    assert visual.contrast_ratio((0x77 / 255,) * 3, (1, 1, 1)) == pytest.approx(4.48, abs=0.02)


def test_png_reader_round_trips_every_filter(tmp_path):
    def px(x, y):
        return ((x * 37 + y * 11) & 0xFF, (x * 5 + y * 90) & 0xFF, (x ^ y) & 0xFF, 255)

    png = tmp_path / "t.png"
    write_png(png, 13, 9, px)
    got = visual.read_png(png)
    assert (got.width, got.height, got.channels) == (13, 9, 4)
    for y in range(9):
        for x in range(13):
            i = (y * 13 + x) * 4
            assert tuple(got.data[i:i + 4]) == px(x, y)


def test_two_overlapping_labels_are_flagged(tmp_path):
    rects = [_label(1, 20, 40, 80, 12), _label(2, 60, 42, 80, 12)]  # 40 x 10 = 400 of 960 px^2: 42%
    _layout(tmp_path / "layout" / "a_game.json", "a_game.png", rects)
    write_png(tmp_path / "a_game.png", 200, 120, lambda x, y: (20, 20, 20, 255))
    res = visual.lint_file(tmp_path / "layout" / "a_game.json")
    assert _checks(res) == ["label_overlap"]
    assert res["findings"][0]["squads"] == [1, 2]
    assert "42%" in res["findings"][0]["detail"]


def test_labels_that_only_touch_are_not_flagged(tmp_path):
    rects = [_label(1, 20, 40, 80, 12), _label(2, 99, 40, 80, 12)]  # 1 px of overlap
    _layout(tmp_path / "l.json", "", rects)
    res = visual.lint_file(tmp_path / "l.json", png=None)
    assert res["findings"] == [] and res["contrast"] is False


def test_low_contrast_label_is_flagged_with_its_ratio(tmp_path):
    # Dim grey text (#555) on a mid-grey ground (#777): well under 4.5:1.
    rects = [_label(7, 20, 40, 80, 12, fg=(0.333, 0.333, 0.333, 1.0))]
    _layout(tmp_path / "c.json", "c.png", rects)
    write_png(tmp_path / "c.png", 200, 120, lambda x, y: (0x77, 0x77, 0x77, 255))
    res = visual.lint_file(tmp_path / "c.json")
    assert res["contrast"] is True
    assert _checks(res) == ["label_contrast"]
    detail = res["findings"][0]["detail"]
    assert "contrast" in detail and "AA needs 4.5" in detail
    ratio = float(detail.split("contrast ")[1].split(":1")[0])
    assert ratio < 4.5


def test_high_contrast_label_passes_and_text_pixels_do_not_win_the_ground(tmp_path):
    # Light text (#dde2ea) on dark ground (#202020), with a text-like stripe of light pixels inside the label.
    def px(x, y):
        return (0xDD, 0xE2, 0xEA, 255) if (x % 7 == 3 and 40 <= y < 52) else (0x20, 0x20, 0x20, 255)

    _layout(tmp_path / "d.json", "d.png", [_label(3, 20, 40, 80, 12)])
    write_png(tmp_path / "d.png", 200, 120, px)
    res = visual.lint_file(tmp_path / "d.json")
    assert res["findings"] == []
    ground = visual.read_png(tmp_path / "d.png").ground(20, 40, 80, 12)
    assert ground[0] < 0.2  # the dark ground won the vote, not the light stripe


def test_label_over_another_squads_footprint_and_footprint_overlap():
    # squad 1's label sits over squad 2's footprint (67% of the label)
    boxes = [
        Box("label", 1, 1, 0, 10, 10, 60, 12),
        Box("footprint", 2, 2, 0, 0, 14, 80, 40),
        Box("footprint", 1, 1, 0, 200, 200, 40, 30),  # its own, far away
        Box("footprint", 3, 2, 0, 300, 0, 40, 30),
        Box("footprint", 4, 2, 0, 330, 0, 40, 30),  # 10 x 30 = 25% of 40 x 30: not beyond the threshold
    ]
    findings, _ = visual.lint(boxes, None)
    assert [f.check for f in findings] == ["label_on_footprint"]
    boxes[4] = Box("footprint", 4, 2, 0, 329, 0, 40, 30)  # 11 x 30 = 27.5%: beyond it
    findings, _ = visual.lint(boxes, None)
    assert sorted(f.check for f in findings) == ["footprint_overlap", "label_on_footprint"]


def test_own_footprint_is_never_a_clash_and_frames_are_separate():
    boxes = [
        Box("label", 1, 1, 0, 10, 10, 60, 12),
        Box("footprint", 1, 1, 0, 0, 0, 80, 40),  # its own footprint
        Box("label", 2, 2, 1, 10, 10, 60, 12),  # the same place, another frame
    ]
    findings, _ = visual.lint(boxes, None)
    assert findings == []


def test_capture_layout_finds_its_image_in_the_capture_folder(tmp_path):
    # capture: <out>/<shot>_game.png, <out>/layout/<shot>_game.json
    (tmp_path / "layout").mkdir()
    _layout(tmp_path / "layout" / "stage_mid_still_game.json", "stage_mid_still_game.png",
            [_label(5, 10, 10, 60, 12, fg=(0.4, 0.4, 0.4, 1.0))])
    write_png(tmp_path / "stage_mid_still_game.png", 200, 120, lambda x, y: (0x80, 0x80, 0x80, 255))
    files = visual.layout_files(tmp_path)
    assert [f.name for f in files] == ["stage_mid_still_game.json"]
    res = visual.lint_file(files[0])
    assert res["image"] and res["contrast"] and _checks(res) == ["label_contrast"]


def test_mock_output_folder_is_found_by_its_layout_suffix(tmp_path):
    _layout(tmp_path / "fire_cues_layout.json", "fire_cues.png", [])
    assert [f.name for f in visual.layout_files(tmp_path)] == ["fire_cues_layout.json"]


def test_cli_usage_error_strict_and_warnings(tmp_path):
    class Args:
        path = str(tmp_path / "nothing")
        png = None
        strict = False

    r = visual_cmd.run(Args())
    assert r.exit_code == 2 and r.checks[0].status == FAIL

    _layout(tmp_path / "x.json", "", [_label(1, 20, 40, 80, 12), _label(2, 60, 42, 80, 12)])
    Args.path = str(tmp_path / "x.json")
    r = visual_cmd.run(Args())
    assert r.exit_code == 0 and r.data["findings"] == 1
    Args.strict = True
    assert visual_cmd.run(Args()).exit_code == 1


def test_pixels_ground_handles_greyscale_and_clipped_rects():
    px = Pixels(4, 2, 1, bytes([0, 0, 255, 255, 0, 0, 255, 255]))
    assert px.ground(-1, -1, 2, 2) == (0.0, 0.0, 0.0)  # only pixel (0, 0) is inside
    assert px.ground(2, 0, 2, 2) == (1.0, 1.0, 1.0)  # columns 2 and 3 are white
    assert px.ground(-5, -5, 2, 2) is None
    assert px.ground(50, 50, 4, 4) is None
