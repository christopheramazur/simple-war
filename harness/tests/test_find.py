from hx.commands.find import search


def test_find_context_and_cap(tmp_path):
    f = tmp_path / "a.txt"
    f.write_text("\n".join(f"line{i}" for i in range(20)) + "\n")
    out, n = search("line5$", [str(tmp_path)], context=1)
    assert n == 1
    assert out[1].endswith(": line5") and ":6:" in out[1]
    assert len(out) == 3
    out, n = search("line", [str(tmp_path)], context=0, max_matches=3)
    assert n == 3 and out[-1].startswith("... truncated")


def test_find_no_match_and_glob(tmp_path):
    (tmp_path / "a.gd").write_text("x\n")
    (tmp_path / "b.md").write_text("x\n")
    out, n = search("x", [str(tmp_path)], glob="*.gd")
    assert n == 1 and "a.gd" in out[0]
    assert search("zzz", [str(tmp_path)])[1] == 0
