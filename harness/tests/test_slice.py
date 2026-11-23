from hx.commands.slice import parse_spec, render


def test_parse_spec():
    assert parse_spec("a/b.gd:5-9") == ("a/b.gd", 5, 9)
    assert parse_spec("a/b.gd:5-") == ("a/b.gd", 5, None)
    assert parse_spec("a/b.gd:-3") == ("a/b.gd", None, 3)
    assert parse_spec("a/b.gd") == ("a/b.gd", None, None)


def test_render_range_and_also(tmp_path):
    a, b = tmp_path / "a.txt", tmp_path / "b.txt"
    a.write_text("\n".join(f"l{i}" for i in range(1, 11)) + "\n")
    b.write_text("x\ny\n")
    out = render([f"{a}:3-4", str(b)])
    assert out[1:3] == ["3: l3", "4: l4"]
    assert out[3].endswith("(1-2 of 2) ==") and out[-1] == "2: y"
    assert render([str(a)], max_lines=2)[-1].startswith("... truncated")
