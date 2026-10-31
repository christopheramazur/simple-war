import pytest

from hx import localmodel, providers
from hx.commands.bonsai import _size
from hx.localmodel import ProbeResult as R

CFG = """
[provider.bonsai]
name = "Bonsai"
kind = "local"
base_url = "http://127.0.0.1:8080/v1"
models = [{ alias = "think", model = "B.gguf" }]

# keep this comment
[provider.bonsai.server]
root = "C:/llm"
exe = "bin/llama-server.exe"
model = "models/B.gguf"
port = 8080
ctx = 32768  # probe result
args = ["-ngl", "99", "--jinja"]

[provider.other]
name = "Other"
kind = "local"

[provider.other.server]
root = "x"
exe = "e"
model = "m"
ctx = 1
args = ["--agent"]
"""


@pytest.fixture
def cfg(tmp_path, monkeypatch):
    f = tmp_path / "providers.toml"
    f.write_text(CFG)
    monkeypatch.setattr(providers, "PROVIDERS_FILE", f)
    return f


def test_command_built_from_config(cfg):
    cmd = localmodel.command("bonsai")
    assert cmd[0].replace("\\", "/") == "C:/llm/bin/llama-server.exe"
    assert cmd[cmd.index("-c") + 1] == "32768" and "--jinja" in cmd
    assert localmodel.command("bonsai", ctx=65536)[cmd.index("-c") + 1] == "65536"


def test_agent_flag_refused(cfg):
    with pytest.raises(ValueError, match="--agent"):
        localmodel.command("other")


def test_apply_ctx_rewrites_only_server_section(cfg):
    localmodel.apply_ctx("bonsai", 98304)
    text = cfg.read_text()
    assert "ctx = 98304" in text and "# keep this comment" in text
    assert "ctx = 1\n" in text  # other provider untouched
    assert providers.load()["bonsai"].server["ctx"] == 98304
    with pytest.raises(ValueError):
        localmodel.apply_ctx("nope", 1)


def test_choose_largest_fit_at_full_speed():
    results = [
        R(204800, loaded=False, error="out of memory"),
        R(163840, loaded=True, fill_ok=True, gen_tps=6.0),   # loaded but spilled to shared memory
        R(131072, loaded=True, fill_ok=False, gen_tps=24.0),  # prefill failed
        R(98304, loaded=True, fill_ok=True, gen_tps=24.5),
        R(32768, loaded=True, fill_ok=True, gen_tps=25.0),
    ]
    assert localmodel.choose(results) == 98304
    assert localmodel.choose([R(1, loaded=False)]) is None


def test_size_parse():
    assert _size("96k") == 98304 and _size("32768") == 32768
