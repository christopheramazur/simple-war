from hx import secrets_scan

# Built by concatenation so this file never contains a literal key shape.
FAKE_ANT = "sk-" + "ant-" + "a" * 40
FAKE_GOOGLE = "AI" + "za" + "B" * 35
FAKE_GH = "gh" + "p_" + "c" * 36


def test_detects_provider_keys():
    text = f"x = '{FAKE_ANT}'\ny = {FAKE_GOOGLE}\nz={FAKE_GH}\n"
    kinds = {k for _, k in secrets_scan.scan_text(text)}
    assert {"anthropic", "google", "github"} <= kinds


def test_allow_marker_skips_line():
    assert secrets_scan.scan_text(f"{FAKE_ANT}  # {secrets_scan.ALLOW_MARKER}") == []


def test_ignores_ordinary_text():
    assert secrets_scan.scan_text("api_key = os.environ['KEY']\nsk-short\n") == []


def test_scan_skips_binary_and_reports_paths(tmp_path):
    (tmp_path / "leak.env").write_text(f"KEY={FAKE_ANT}\n")
    (tmp_path / "blob.bin").write_bytes(b"\0\0" + FAKE_ANT.encode())
    found = secrets_scan.scan(tmp_path, ["leak.env", "blob.bin", "missing.txt"])
    assert [(f.path, f.line, f.kind) for f in found] == [("leak.env", 1, "anthropic")]


def test_candidate_files_respects_gitignore(fake_repo):
    (fake_repo / ".gitignore").write_text("secret.env\n")
    (fake_repo / "secret.env").write_text("x")
    (fake_repo / "keep.txt").write_text("x")
    files = secrets_scan.candidate_files(fake_repo)
    assert "keep.txt" in files and "secret.env" not in files
