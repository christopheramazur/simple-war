from hx.commands.scan import scan


def test_scan_lists_and_matches(tmp_path):
    (tmp_path / "Mailbox.md").write_text("x")
    (tmp_path / "sub" / "deep").mkdir(parents=True)
    (tmp_path / "sub" / "inbox.txt").write_text("x")
    (tmp_path / "sub" / "deep" / "INBOX2.txt").write_text("x")
    listing, found = scan(tmp_path, depth=2, names=["*mail*", "*inbox*"])
    assert listing == ["Mailbox.md", "sub/"]
    assert [Path.name for Path in map(__import__("pathlib").Path, found)] == ["Mailbox.md", "inbox.txt"]
    assert scan(tmp_path, depth=3, names=["*inbox*"])[1][-1].endswith("INBOX2.txt")
    assert scan(tmp_path)[1] == []
