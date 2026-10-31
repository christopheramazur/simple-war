import json

import keyring
import pytest

from hx import ledger, providers
from hx.cli import main
from hx.gateway import budget, config

from test_secrets_providers import MemoryKeyring

ROSTER = """
[provider.claude-pro]
name = "Pro"
kind = "subscription"
models = [{ alias = "x", model = "never" }]

[provider.bonsai]
name = "Bonsai"
kind = "local"
base_url = "http://127.0.0.1:8080/v1"
litellm_prefix = "openai/"
models = [
  { alias = "think", model = "B.gguf" },
  { alias = "nothink", model = "B.gguf", params = { extra_body = { chat_template_kwargs = { enable_thinking = false } } } },
]

[provider.groq]
name = "Groq"
kind = "api"
keys = ["GROQ_API_KEY"]
base_url = "https://api.groq.com/openai/v1"
litellm_prefix = "groq/"
models = [{ alias = "l70", model = "llama-70b" }]

[provider.cloudflare]
name = "CF"
kind = "api"
keys = ["CLOUDFLARE_API_KEY", "CLOUDFLARE_ACCOUNT_ID"]
base_url = "https://api.cloudflare.com/client/v4/accounts/{CLOUDFLARE_ACCOUNT_ID}/ai/v1"
litellm_prefix = "cloudflare/"
models = [{ alias = "llama", model = "@cf/meta/llama" }]

[provider.zen]
name = "Zen"
kind = "client"
cli = "opencode"
models = [{ alias = "free", model = "x" }]
"""


@pytest.fixture
def roster(tmp_path, monkeypatch):
    old = keyring.get_keyring()
    keyring.set_keyring(MemoryKeyring())
    cfg = tmp_path / "providers.toml"
    cfg.write_text(ROSTER)
    monkeypatch.setattr(providers, "PROVIDERS_FILE", cfg)
    monkeypatch.setenv("HX_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv("HX_SECRETS_FILE", str(tmp_path / "s.env"))
    for k in ("GROQ_API_KEY", "CLOUDFLARE_API_KEY", "CLOUDFLARE_ACCOUNT_ID"):
        monkeypatch.delenv(k, raising=False)
    yield providers.load()
    keyring.set_keyring(old)


def test_only_keyed_api_and_local_providers_are_served(roster):
    models, skipped = config.deployments(roster)
    names = [m["model_name"] for m in models]
    assert names == ["bonsai/think", "bonsai/nothink"]  # no subscription, no client, no keyless api
    assert skipped == ["groq: missing GROQ_API_KEY", "cloudflare: missing CLOUDFLARE_API_KEY, CLOUDFLARE_ACCOUNT_ID"]
    nothink = models[1]["litellm_params"]
    assert nothink == {"model": "openai/B.gguf", "api_base": "http://127.0.0.1:8080/v1", "api_key": "none",
                       "extra_body": {"chat_template_kwargs": {"enable_thinking": False}}}


def test_keys_are_referenced_never_inlined(roster, monkeypatch):
    from hx import keystore
    keystore.set("GROQ_API_KEY", "gsk-secret-value")
    keystore.set("CLOUDFLARE_API_KEY", "cf-secret")
    keystore.set("CLOUDFLARE_ACCOUNT_ID", "acct")
    path, skipped, n = config.write(roster)
    text = path.read_text()
    assert "gsk-secret-value" not in text and "cf-secret" not in text
    cfg = json.loads(text)
    by = {m["model_name"]: m["litellm_params"] for m in cfg["model_list"]}
    assert by["groq/l70"]["api_key"] == "os.environ/GROQ_API_KEY"
    assert "api_base" not in by["cloudflare/llama"]  # templated URL left to LiteLLM
    assert cfg["general_settings"]["master_key"] == "os.environ/HX_GATEWAY_KEY"
    assert cfg["litellm_settings"]["num_retries"] == 0
    assert (path.parent / "hx_callbacks.py").exists() and n == 4 and not skipped


def test_alias_map(roster):
    m = config.alias_map(roster)
    assert m["bonsai/nothink"] == "bonsai" and m["groq/l70"] == "groq"


def test_ingest_gateway_log(roster, capsys, monkeypatch):
    monkeypatch.setenv("HX_CLAUDE_PROJECTS", str(config.gateway_dir() / "none"))
    budget.append_log({"ts": "2026-10-31T13:00:00.000+00:00", "provider": "bonsai", "model_group": "bonsai/nothink",
                       "status": "success", "call_id": "c1", "prompt_tokens": 400, "completion_tokens": 20,
                       "cost_usd": 0.0, "caller": "bench"})
    budget.append_log({"ts": "2026-10-31T13:00:05.000+00:00", "provider": "bonsai", "model_group": "bonsai/nothink",
                       "status": "refused", "error": "bonsai: free-tier rpm 1 reached"})
    assert main(["ingest", "--json"]) == 0
    assert json.loads(capsys.readouterr().out)["data"]["gateway_calls"] == 1
    con = ledger.connect()
    row = con.execute("SELECT client, provider, model, input_tokens, est_usd, agent_id FROM call").fetchone()
    assert row == ("gateway", "bonsai", "bonsai/nothink", 400, 0.0, "bench")  # reprice didn't clobber it
    ev = con.execute("SELECT kind, detail FROM event").fetchone()
    assert ev[0] == "gateway_refused" and "rpm 1" in ev[1]
    con.close()


def test_adapter_sends_gateway_key(roster, monkeypatch):
    from hx import keystore
    from hx.bench import adapters
    keystore.set("HX_GATEWAY_KEY", "hx-local")
    assert adapters._auth({"api_key_secret": "HX_GATEWAY_KEY"}) == {"Authorization": "Bearer hx-local"}
    assert adapters._auth({}) == {}
