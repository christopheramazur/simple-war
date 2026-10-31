"""API key storage (DESIGN.md §4, Q31). Keys never live in the repo and are never printed.

Lookup order for a key name such as OPENROUTER_API_KEY:
  1. the process environment (explicit override, e.g. in a container)
  2. the OS keyring (Windows Credential Manager), service "simple-war-hx"
  3. the fallback file %USERPROFILE%/.hx/secrets.env (for WSL/containers without a keyring)

Only the user stores keys (`hx secrets set NAME` prompts without echo). Agents may check
presence (`hx secrets list`) but never read or print values.
"""

from __future__ import annotations

import os
import re
from pathlib import Path

SERVICE = "simple-war-hx"
_NAME = re.compile(r"^[A-Z][A-Z0-9_]{2,63}$")


def secrets_file() -> Path:
    return Path(os.environ.get("HX_SECRETS_FILE") or Path.home() / ".hx" / "secrets.env")


def valid_name(name: str) -> bool:
    return bool(_NAME.match(name))


# ---------- keyring backend ----------

def _keyring():
    """The keyring module if a real backend is available, else None."""
    try:
        import keyring
        from keyring.backends import fail
    except ImportError:
        return None
    return None if isinstance(keyring.get_keyring(), fail.Keyring) else keyring


def keyring_backend() -> str:
    kr = _keyring()
    return type(kr.get_keyring()).__name__ if kr else "unavailable"


# ---------- file backend ----------

def _read_file() -> dict[str, str]:
    f = secrets_file()
    if not f.exists():
        return {}
    out = {}
    for line in f.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def _write_file(entries: dict[str, str]) -> None:
    f = secrets_file()
    f.parent.mkdir(parents=True, exist_ok=True)
    body = "# hx secrets fallback. Do not commit or share. Managed by `hx secrets`.\n"
    body += "".join(f"{k}={v}\n" for k, v in sorted(entries.items()))
    f.write_text(body, encoding="utf-8")
    try:
        f.chmod(0o600)  # effective on POSIX/WSL; on Windows the file sits in the user's profile
    except OSError:
        pass


# ---------- API ----------

def where(name: str) -> str | None:
    """Which source would supply this key: 'env', 'keyring', 'file' or None. Never returns the value."""
    if os.environ.get(name):
        return "env"
    kr = _keyring()
    if kr and kr.get_password(SERVICE, name):
        return "keyring"
    if name in _read_file():
        return "file"
    return None


def get(name: str) -> str | None:
    """For in-process use only (e.g. building the gateway's environment). Never log the result."""
    if os.environ.get(name):
        return os.environ[name]
    kr = _keyring()
    if kr:
        v = kr.get_password(SERVICE, name)
        if v:
            return v
    return _read_file().get(name)


def set(name: str, value: str, backend: str = "keyring") -> str:  # noqa: A001 (mirrors keyring API)
    if not valid_name(name):
        raise ValueError(f"bad key name {name!r}: use UPPER_SNAKE_CASE like OPENROUTER_API_KEY")
    value = value.strip()
    if not value:
        raise ValueError("empty value")
    if backend == "keyring":
        kr = _keyring()
        if kr is None:
            raise RuntimeError("no OS keyring available; use --file")
        kr.set_password(SERVICE, name, value)
    elif backend == "file":
        entries = _read_file()
        entries[name] = value
        _write_file(entries)
    else:
        raise ValueError(f"unknown backend {backend}")
    return backend


def delete(name: str) -> list[str]:
    removed = []
    kr = _keyring()
    if kr and kr.get_password(SERVICE, name):
        kr.delete_password(SERVICE, name)
        removed.append("keyring")
    entries = _read_file()
    if name in entries:
        del entries[name]
        _write_file(entries)
        removed.append("file")
    return removed


def file_names() -> list[str]:
    return sorted(_read_file())


def env_for(names: list[str]) -> dict[str, str]:
    """Environment fragment for launching a child process (e.g. the gateway). Missing keys are omitted."""
    return {n: v for n in names if (v := get(n))}
