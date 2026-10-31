import io
import json

import keyring
import pytest
from keyring.backend import KeyringBackend

from hx import keystore, providers
from hx.cli import main

ROSTER = """
[provider.claude-pro]
name = "Claude Pro"
kind = "subscription"
monthly_budget_usd = 0

[provider.openrouter]
name = "OpenRouter"
kind = "api"
keys = ["OPENROUTER_API_KEY"]
limits = { rpm = 20, rpd = 50 }
trains_on_data = false
steps = ["Sign up", "Create a key"]

[provider.cloudflare]
name = "Cloudflare Workers AI"
kind = "api"
keys = ["CLOUDFLARE_API_KEY", "CLOUDFLARE_ACCOUNT_ID"]

[provider.zen]
name = "OpenCode Zen"
kind = "client"
cli = "definitely-not-installed-cli"
steps = ["Install opencode"]
"""
FAKE = "sk-" + "or-v1-" + "z" * 40  # never a literal key shape in this file


class MemoryKeyring(KeyringBackend):
    priority = 1

    def __init__(self):
        super().__init__()
        self.store = {}

    def get_password(self, service, user):
        return self.store.get((service, user))

    def set_password(self, service, user, pw):
        self.store[(service, user)] = pw

    def delete_password(self, service, user):
        del self.store[(service, user)]


@pytest.fixture(autouse=True)
def env(tmp_path, monkeypatch):
    kr = MemoryKeyring()
    old = keyring.get_keyring()
    keyring.set_keyring(kr)
    cfg = tmp_path / "providers.toml"
    cfg.write_text(ROSTER)
    monkeypatch.setattr(providers, "PROVIDERS_FILE", cfg)
    monkeypatch.setenv("HX_SECRETS_FILE", str(tmp_path / "secrets.env"))
    for k in ("OPENROUTER_API_KEY", "CLOUDFLARE_API_KEY", "CLOUDFLARE_ACCOUNT_ID"):
        monkeypatch.delenv(k, raising=False)
    yield kr
    keyring.set_keyring(old)


def test_lookup_order_env_keyring_file(monkeypatch):
    assert keystore.where("OPENROUTER_API_KEY") is None
    keystore.set("OPENROUTER_API_KEY", "fromfile", "file")
    assert (keystore.where("OPENROUTER_API_KEY"), keystore.get("OPENROUTER_API_KEY")) == ("file", "fromfile")
    keystore.set("OPENROUTER_API_KEY", " fromkeyring \n")
    assert (keystore.where("OPENROUTER_API_KEY"), keystore.get("OPENROUTER_API_KEY")) == ("keyring", "fromkeyring")
    monkeypatch.setenv("OPENROUTER_API_KEY", "fromenv")
    assert keystore.where("OPENROUTER_API_KEY") == "env"
    monkeypatch.delenv("OPENROUTER_API_KEY")
    assert keystore.delete("OPENROUTER_API_KEY") == ["keyring", "file"]
    assert keystore.where("OPENROUTER_API_KEY") is None


def test_rejects_bad_names_and_empty_values():
    with pytest.raises(ValueError):
        keystore.set("lowercase", "x")
    with pytest.raises(ValueError):
        keystore.set("GOOD_NAME", "   ")


def test_set_via_stdin_never_echoes_value(monkeypatch, capsys):
    monkeypatch.setattr("sys.stdin", io.StringIO(FAKE + "\n"))
    assert main(["secrets", "set", "OPENROUTER_API_KEY", "--stdin"]) == 0
    out = capsys.readouterr().out
    assert FAKE not in out and "keyring" in out
    assert keystore.get("OPENROUTER_API_KEY") == FAKE


def test_set_refuses_without_terminal(monkeypatch, capsys):
    monkeypatch.setattr("sys.stdin", io.StringIO(""))  # not a tty
    assert main(["secrets", "set", "OPENROUTER_API_KEY"]) == 1
    assert "no terminal" in capsys.readouterr().out


def test_list_shows_sources_not_values(capsys):
    keystore.set("OPENROUTER_API_KEY", FAKE)
    keystore.set("STRAY_KEY", "x" * 30, "file")
    main(["secrets", "list", "--json"])
    raw = capsys.readouterr().out
    assert FAKE not in raw and "x" * 30 not in raw
    rows = {r["key"]: r for r in json.loads(raw)["tables"]["keys"]}
    assert rows["OPENROUTER_API_KEY"]["source"] == "keyring"
    assert rows["CLOUDFLARE_ACCOUNT_ID"]["source"] == "missing"
    assert rows["STRAY_KEY"]["provider"] == "(unreferenced)"


def test_providers_readiness_and_checklist(capsys):
    keystore.set("CLOUDFLARE_API_KEY", "abc")
    main(["providers", "--json"])
    rows = {r["provider"]: r for r in json.loads(capsys.readouterr().out)["tables"]["providers"]}
    assert rows["claude-pro"]["ready"] and not rows["openrouter"]["ready"]
    assert rows["cloudflare"]["status"] == "missing CLOUDFLARE_ACCOUNT_ID"
    assert rows["openrouter"]["free_limits"] == "rpm 20, rpd 50" and rows["openrouter"]["trains"] == "no"
    assert not rows["zen"]["ready"]
    main(["providers", "--checklist"])
    out = capsys.readouterr().out
    assert "hx secrets set OPENROUTER_API_KEY" in out and "hx secrets set CLOUDFLARE_ACCOUNT_ID" in out
    assert "hx secrets set CLOUDFLARE_API_KEY" not in out  # already stored
    assert "Install opencode" in out and "Claude Pro" not in out


def test_env_for_omits_missing():
    keystore.set("OPENROUTER_API_KEY", "v1")
    assert keystore.env_for(["OPENROUTER_API_KEY", "CLOUDFLARE_API_KEY"]) == {"OPENROUTER_API_KEY": "v1"}


def test_config_validation(tmp_path):
    bad = tmp_path / "bad.toml"
    bad.write_text('[provider.x]\nname = "X"\nkind = "weird"\n')
    with pytest.raises(ValueError):
        providers.load(bad)
