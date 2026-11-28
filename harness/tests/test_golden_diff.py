"""hx visual diff (sw-tho3.13, U1 B13a): exact per-pixel golden diff with a numeric tolerance, synthetic fixtures.

Thresholds used here (explicit, so the tests state them): max_channel_delta 8, max_changed_share 1%.
Fixture: a 200 x 120 image, dark ground (30,30,30), one 80 x 12 light label block (220,220,220).
A 1-pixel shift of the label changes 24 pixels (0.10%): within. A 20-pixel move changes 2 x 20 x 12 = 480
pixels (2.00%): over. Brightness jitter of 8 on every pixel is inside max_channel_delta: identical.
"""

from __future__ import annotations

import argparse
import json

import pytest

from hx import golden, visual
from hx.commands import visual as visual_cmd
from hx.output import FAIL
from hx.golden import Tolerance

TOL = Tolerance(max_channel_delta=8, max_changed_share=0.01)
W, H = 200, 120


def _rgb(fn, w=W, h=H) -> bytes:
    return bytes(c for y in range(h) for x in range(w) for c in fn(x, y))


def _label_at(x0, y0, w=80, h=12, ground=(30, 30, 30), ink=(220, 220, 220)):
    return lambda x, y: ink if (x0 <= x < x0 + w and y0 <= y < y0 + h) else ground


def _save(path, fn, w=W, h=H):
    path.parent.mkdir(parents=True, exist_ok=True)
    golden.write_rgb_png(path, w, h, _rgb(fn, w, h))
    return path


def _capture(tmp_path, shots: dict):
    cap = tmp_path / "cap"
    for name, fn in shots.items():
        _save(cap / name, fn)
    return cap


def _status(res, name):
    return next(s for s in res if s.name == name)


def test_tolerance_is_read_from_config():
    cfg = golden.load_tolerance()
    assert cfg.max_channel_delta == 8
    assert cfg.max_changed_share == pytest.approx(0.01)


def test_identical_captures_diff_to_zero(tmp_path):
    cap = _capture(tmp_path, {"stage_mid_game.png": _label_at(20, 40)})
    gold = tmp_path / "gold"
    golden.accept(cap, gold)
    res = golden.diff_capture(cap, gold, tmp_path / "out", TOL)
    s = _status(res, "stage_mid_game.png")
    assert (s.status, s.changed, s.max_delta, s.diff_png) == ("same", 0, 0, None)
    assert not any(x.failed for x in res)


def test_one_pixel_shift_is_under_tolerance(tmp_path):
    gold = _save(tmp_path / "gold" / "a.png", _label_at(20, 40))
    cap = _save(tmp_path / "cap" / "a.png", _label_at(21, 40))
    s = golden.compare_shot("a.png", gold, cap, TOL, tmp_path / "out" / "a.png")
    assert s.changed == 24  # the old left column (12 px) and the new right column (12 px)
    assert s.status == "within" and s.share == pytest.approx(24 / (W * H))
    assert not s.failed
    assert s.diff_png is not None and visual.read_png(s.diff_png).width == W  # diff PNG still written


def test_moved_label_block_is_over_tolerance(tmp_path):
    gold = _save(tmp_path / "gold" / "a.png", _label_at(20, 40))
    cap = _save(tmp_path / "cap" / "a.png", _label_at(40, 40))
    s = golden.compare_shot("a.png", gold, cap, TOL)
    assert s.changed == 480  # 2 x 20 columns x 12 rows
    assert s.status == "over" and s.failed
    assert s.share == pytest.approx(0.02)
    assert "2.00% of pixels changed (limit 1.00%)" in s.detail


def test_channel_jitter_inside_max_channel_delta_is_identical_and_outside_is_over(tmp_path):
    base = _label_at(20, 40)
    near = lambda x, y: tuple(min(255, c + 8) for c in base(x, y))  # 8 is inside max_channel_delta
    far = lambda x, y: tuple(min(255, c + 9) for c in base(x, y))  # 9 is not
    gold = _save(tmp_path / "gold" / "a.png", base)
    assert golden.compare_shot("a.png", gold, _save(tmp_path / "n" / "a.png", near), TOL).status == "same"
    assert golden.compare_shot("a.png", gold, _save(tmp_path / "f" / "a.png", far), TOL).status == "over"


def test_size_mismatch_fails(tmp_path):
    gold = _save(tmp_path / "gold" / "a.png", _label_at(20, 40))
    cap = _save(tmp_path / "cap" / "a.png", _label_at(20, 40), w=W + 2)
    s = golden.compare_shot("a.png", gold, cap, TOL)
    assert s.status == "mismatch" and s.failed
    assert "202x120" in s.detail


def test_new_and_missing_shots_are_advisory(tmp_path):
    cap = _capture(tmp_path, {"new.png": _label_at(20, 40)})
    gold = _save(tmp_path / "gold" / "gone.png", _label_at(20, 40))
    res = golden.diff_capture(cap, tmp_path / "gold", None, TOL)
    assert _status(res, "new.png").status == "new" and not _status(res, "new.png").failed
    assert _status(res, "gone.png").status == "missing" and not _status(res, "gone.png").failed
    assert gold.exists()


def test_accept_replaces_the_golden_set_with_the_capture(tmp_path):
    cap = _capture(tmp_path, {"s1.png": _label_at(20, 40)})
    (cap / "layout").mkdir()
    (cap / "layout" / "s1.json").write_text(json.dumps({"rects": []}), encoding="utf-8")
    gold = tmp_path / "gold"
    _save(gold / "stale.png", _label_at(0, 0))
    n = golden.accept(cap, gold)
    assert n == 2
    assert not (gold / "stale.png").exists()  # the old set is replaced, not merged
    assert (gold / "s1.png").is_file() and (gold / "layout" / "s1.json").is_file()
    assert all(x.status == "same" for x in golden.diff_capture(cap, gold, None, TOL) if x.name == "s1.png")


def _cli_args(**kw):
    base = dict(action="diff", capture="", golden="g", accept=False)
    base.update(kw)
    return argparse.Namespace(**base)


def test_cli_diff_exit_codes_and_accept(tmp_path, monkeypatch):
    monkeypatch.setenv("HX_REPO_ROOT", str(tmp_path))
    data = tmp_path / "data" / "visual"
    cap = data / "run1"
    _save(cap / "s.png", _label_at(20, 40))

    # no golden yet: usage error, exit 2
    assert visual_cmd.run(_cli_args(capture="run1")).exit_code == 2

    # accept creates it and exits 0
    r = visual_cmd.run(_cli_args(capture="run1", accept=True))
    assert r.exit_code == 0 and r.data["files"] == 1

    # identical: exit 0
    assert visual_cmd.run(_cli_args(capture="run1")).exit_code == 0

    # a label moved 20 px: over tolerance, exit 1, the diff PNG is written
    _save(cap / "s.png", _label_at(40, 40))
    r = visual_cmd.run(_cli_args(capture="run1"))
    assert r.exit_code == 1 and r.data["over"] == 1
    fail = [c for c in r.checks if c.status == FAIL]
    assert fail and "s.png: over tolerance" in fail[0].name
    assert (data / "diff" / "g" / "run1" / "s.png").is_file()

    # a 1-pixel shift: within, exit 0
    _save(cap / "s.png", _label_at(21, 40))
    r = visual_cmd.run(_cli_args(capture="run1"))
    assert r.exit_code == 0 and r.data["within"] == 1 and r.data["over"] == 0


def test_cli_refuses_to_accept_a_capture_into_itself(tmp_path, monkeypatch):
    monkeypatch.setenv("HX_REPO_ROOT", str(tmp_path))
    cap = tmp_path / "data" / "visual" / "run1"
    _save(cap / "s.png", _label_at(20, 40))
    r = visual_cmd.run(_cli_args(capture="run1", golden="x", accept=True))
    assert r.exit_code == 0
    # the golden set is data/visual/golden/x; accepting that folder as its own capture must not delete it
    inside = tmp_path / "data" / "visual" / "golden" / "x"
    _save(inside / "t.png", _label_at(20, 40))
    r = visual_cmd.run(_cli_args(capture=str(inside), golden="x", accept=True))
    assert r.exit_code == 2 and (inside / "t.png").is_file()
