"""Qwen swarm: a supervisor that keeps role agents (headless OpenCode turns on Qwen4 Max) looping for days.

One `opencode run` is one agent turn. The supervisor re-runs each role on its cadence and carries state
between turns in files: role prompts (harness/swarm/roles/), inboxes and job records (harness/data/swarm/),
and committed outputs (docs/swarm/). See harness/swarm/README.md.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import threading
import time
import tomllib
import urllib.request
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path

from hx import background, clock, paths

MODEL = "hx/nous/qwen4-max"            # the only model the swarm may run
GATEWAY_MODEL = "nous/qwen4-max"
ROOT = paths.main_root()
SWARM = ROOT / "harness" / "swarm"
ROLES = SWARM / "roles"
STATE = ROOT / "harness" / "data" / "swarm"
DOCS = ROOT / "docs" / "swarm"
WT_ROOT = ROOT.parent / f"{ROOT.name}-worktrees"
OC_CONFIG = SWARM / "opencode.json"
DONE = {"merged", "rejected"}
PROTECTED = {"harness/src/hx/swarm.py", "harness/src/hx/commands/swarm.py", "harness/swarm/opencode.json",
             "harness/swarm/roles/_common.md", "harness/src/hx/gateway/litellm_hooks.py", "harness/config/providers.toml",
             "harness/src/hx/commands/delegate.py", "harness/src/hx/gateway/pacer.py", "opencode.json", ".mcp.json"}


def now() -> datetime:
    return datetime.now(timezone.utc)


def stamp(t: datetime | None = None) -> str:
    return (t or now()).strftime("%Y%m%dT%H%M%SZ")


def cfg() -> dict:
    return tomllib.loads((SWARM / "swarm.toml").read_text(encoding="utf-8"))


def cfg_mtime() -> float:
    try:
        return (SWARM / "swarm.toml").stat().st_mtime
    except OSError:
        return 0.0


def cfg_diff(old: dict, new: dict, prefix: str = "") -> list[str]:
    """Dotted keys whose value differs between two config dicts (added, removed or changed)."""
    out = []
    for k in sorted(set(old) | set(new), key=str):
        a, b, key = old.get(k), new.get(k), f"{prefix}{k}"
        if isinstance(a, dict) and isinstance(b, dict):
            out += cfg_diff(a, b, key + ".")
        elif a != b:
            out.append(key)
    return out


def _write(p: Path, text: str) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8", newline="\n")


def _append(p: Path, text: str) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    with p.open("a", encoding="utf-8", newline="\n") as f:
        f.write(text)


def log(msg: str) -> None:
    _append(STATE / "supervisor.log", f"{now().isoformat(timespec='seconds')} {msg}\n")


def event(kind: str, **kw) -> None:
    _append(STATE / "events.jsonl", json.dumps({"ts": now().isoformat(timespec="seconds"), "kind": kind, **kw}) + "\n")


def events(since: datetime | None = None) -> list[dict]:
    f = STATE / "events.jsonl"
    if not f.exists():
        return []
    out = []
    for line in f.read_text(encoding="utf-8").splitlines():
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if since is None or datetime.fromisoformat(e["ts"]) >= since:
            out.append(e)
    return out


# ---------------------------------------------------------------- state (one JSON file, guarded)

_state_lock = threading.Lock()


def load_state() -> dict:
    f = STATE / "state.json"
    if f.exists():
        return json.loads(f.read_text(encoding="utf-8"))
    return {"generation": 1, "alert_streak": 0, "turns": {}, "postmortems": [], "started": now().isoformat()}


def update_state(fn) -> dict:
    with _state_lock, file_lock("state"):
        s = load_state()
        fn(s)
        _write(STATE / "state.json", json.dumps(s, indent=1))
        return s


@contextmanager
def file_lock(name: str, timeout: float = 600, stale: float = 900):
    """Cross-process lock: agents run `hx swarm merge` in their own processes."""
    p = STATE / "locks" / f"{name}.lock"
    p.parent.mkdir(parents=True, exist_ok=True)
    t0 = time.time()
    while True:
        try:
            fd = os.open(p, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            os.write(fd, str(os.getpid()).encode())
            os.close(fd)
            break
        except FileExistsError:
            try:
                if time.time() - p.stat().st_mtime > stale:
                    p.unlink(missing_ok=True)
                    continue
            except OSError:
                pass
            if time.time() - t0 > timeout:
                raise TimeoutError(f"lock {name} busy")
            time.sleep(0.5)
    try:
        yield
    finally:
        p.unlink(missing_ok=True)


# ---------------------------------------------------------------- mail

def roster(c: dict | None = None) -> dict[str, list[str]]:
    c = c or cfg()
    return {"orchestrator": ["orchestrator"], "auditor": ["auditor"], "designers": list(c["designers"]["roles"]),
            "researchers": list(c["researchers"]["roles"])}


def send_mail(to: str, sender: str, body: str) -> list[str]:
    groups = roster()
    names = groups.get(to) or ([to] if any(to in g for g in groups.values()) else [])
    if not names:
        raise ValueError(f"unknown recipient {to!r}; use one of {sorted(set(groups) | {n for g in groups.values() for n in g})}")
    for n in names:
        _write(STATE / "mail" / n / f"{stamp()}-{sender}-{os.getpid()}.md", f"From: {sender} ({clock.stamp()})\n\n{body.strip()}\n")
    return names


def inbox_count(role: str) -> int:
    d = STATE / "mail" / role
    return sum(1 for _ in d.glob("*.md")) if d.exists() else 0


def take_mail(role: str) -> str:
    d = STATE / "mail" / role
    if not d.exists():
        return ""
    parts = []
    for f in sorted(d.glob("*.md")):
        parts.append(f.read_text(encoding="utf-8"))
        dest = d / "read" / f.name
        dest.parent.mkdir(exist_ok=True)
        f.replace(dest)
    return "\n---\n".join(parts)


# ---------------------------------------------------------------- git helpers

def git(*args: str, cwd: Path = ROOT, check: bool = False) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, encoding="utf-8",
                          errors="replace", check=check, timeout=600)


def commit_docs(msg: str, extra: list[str] | None = None) -> str:
    """Commit swarm docs (and given paths) in the main checkout and push. Returns a short status."""
    with file_lock("git"):
        targets = ["docs/swarm", "harness/swarm/roles", *(extra or [])]
        git("add", "--", *[t for t in targets if (ROOT / t).exists()])
        if not git("diff", "--cached", "--quiet").returncode:
            return "nothing to commit"
        r = git("commit", "-q", "-m", f"{msg}\n\nCo-Authored-By: Qwen4 Max (swarm) <noreply@nousresearch.com>")
        if r.returncode:
            return "commit failed: " + (r.stderr or r.stdout)[-300:]
        p = git("push", "-q", "origin", "HEAD")
        return "committed" + ("" if not p.returncode else " (push failed: " + p.stderr[-200:] + ")")


# ---------------------------------------------------------------- worker jobs

def job_path(bead: str) -> Path:
    return STATE / "workers" / f"{bead}.json"


def load_job(bead: str) -> dict | None:
    p = job_path(bead)
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else None


def save_job(j: dict) -> None:
    _write(job_path(j["bead"]), json.dumps(j, indent=1))


def jobs() -> list[dict]:
    d = STATE / "workers"
    return [json.loads(p.read_text(encoding="utf-8")) for p in sorted(d.glob("*.json"))] if d.exists() else []


def fill_gitlinks(wt: Path) -> list[str]:
    """Gitlink folders (GD-Agentic-Skills, addons/custom_graph_editor) are empty in a new worktree, and in the main
    checkout they are plain folders without their own .git. Copy them in: a separate copy, never a link back."""
    import shutil
    done = []
    for line in git("ls-files", "-s", cwd=wt).stdout.splitlines():
        if not line.startswith("160000 "):
            continue
        path = line.split("\t", 1)[1]
        src, dst = ROOT / path, wt / path
        if not src.is_dir() or (dst.exists() and any(dst.iterdir())):
            continue
        try:
            shutil.copytree(src, dst, dirs_exist_ok=True, ignore=shutil.ignore_patterns(".git"))
            done.append(path)
        except OSError as e:
            log(f"fill_gitlinks {path}: {e!r}")
    return done


RESPAWNABLE = DONE | {"failed", "partial", "done"}


def save_wip(wt: Path, why: str) -> bool:
    """Commit whatever a worker left uncommitted, so a timed-out turn's work survives for the next attempt."""
    if not wt.exists() or not git("status", "--porcelain", cwd=wt).stdout.strip():
        return False
    git("add", "-A", cwd=wt)
    r = git("commit", "-q", "--no-verify", "-m", f"WIP: {why}", "-m",
            "Saved by the swarm supervisor; the next attempt continues from here.", cwd=wt)
    return not r.returncode


def spawn_worker(bead: str, note: str = "", fresh: bool = False) -> dict:
    """Queue a worker. A bead with an earlier branch continues from it (its commits and WIP survive) unless fresh."""
    if not re.fullmatch(r"[A-Za-z0-9._-]+", bead):
        raise ValueError("bad bead id")
    c = cfg()
    j = load_job(bead)
    if j and j["status"] not in RESPAWNABLE:
        raise ValueError(f"{bead} already has a {j['status']} worker")
    active = [x for x in jobs() if x["status"] in ("queued", "running", "done", "partial") and x["bead"] != bead]
    if len(active) >= c["workers"]["max_open"]:
        raise ValueError(f"{len(active)} worker jobs are open (queued/running/awaiting review); merge or reject some first")
    show = subprocess.run(["bd", "show", bead], cwd=ROOT, capture_output=True, text=True, encoding="utf-8",
                          errors="replace", stdin=subprocess.DEVNULL, timeout=60)
    if show.returncode:
        raise ValueError(f"bd show {bead} failed: {show.stderr.strip()[-200:]}")
    wt, branch = WT_ROOT / bead, f"swarm/{bead}"
    with file_lock("git"):
        has_branch = not git("rev-parse", "--verify", "-q", branch).returncode
        if fresh or not has_branch:
            if wt.exists():
                git("worktree", "remove", "--force", str(wt))
            git("branch", "-D", branch)
            r = git("worktree", "add", "-q", "-b", branch, str(wt), "HEAD")
            continued = False
        else:
            save_wip(wt, "uncommitted work from the previous attempt")
            r = subprocess.CompletedProcess([], 0, "", "")
            if not wt.exists():
                git("worktree", "prune")
                r = git("worktree", "add", "-q", str(wt), branch)
            continued = True
        if r.returncode:
            raise ValueError("worktree add failed: " + r.stderr[-300:])
        base = git("merge-base", "HEAD", branch).stdout.strip() or git("rev-parse", "HEAD").stdout.strip()
    fill_gitlinks(wt)
    attempts = (j or {}).get("attempts", 0) + 1
    j = {"bead": bead, "status": "queued", "worktree": str(wt), "branch": branch, "base": base,
         "created": now().isoformat(timespec="seconds"), "attempts": attempts, "note": note,
         "continued": continued, "bead_text": show.stdout[-6000:], "summary": ""}
    save_job(j)
    event("spawn", bead=bead, attempts=attempts, continued=continued)
    return j


def _checks_for(changed: list[str]) -> list[list[str]]:
    checks = []
    # the Godot check's own tooling counts as game code: a lint change that only ran pytest turned main red (sw-iqv)
    if any(not f.startswith(("harness/", "docs/", ".beads/")) or f.startswith("harness/godot/")
           or f == "harness/src/hx/commands/godot.py" for f in changed):
        # not ["bash", "harness/bin/hx", ...]: Windows resolves a bare "bash" in System32 (WSL) before PATH
        # a fresh worktree has no .godot import cache: GUT cannot see class_names until an import runs
        checks.append(["uv", "run", "--project", "harness", "--quiet", "hx", "godot", "check"])
        checks.append(["uv", "run", "--project", "harness", "--quiet", "hx", "godot", "test"])
    if any(f.startswith("harness/") for f in changed):
        checks.append(["uv", "run", "--project", "harness", "pytest", "-q", "-x"])
    return checks


class MergeRed(ValueError):
    """The tests failed on the branch with main merged in; main is untouched."""

    def __init__(self, check: str, msg: str) -> None:
        super().__init__(msg)
        self.check = check


def merge_branch(branch: str, wt: Path, timeout: int, protected: frozenset[str] | set[str] = frozenset()) -> tuple[list[str], str]:
    """Bring main into `branch` (checked out at `wt`), run the tests there, then fast-forward main, push, and remove
    the worktree and branch. Main never goes red. Returns (check names, push error or ""). Shared by the swarm and
    hx autopilot; both take the same `git` lock, so their merges never interleave."""
    env = {k: v for k, v in os.environ.items() if k != "HX_REPO_ROOT"}
    for _ in range(3):
        with file_lock("git"):
            if git("rev-list", "--count", f"HEAD..{branch}").stdout.strip() in ("", "0"):
                raise ValueError(f"{branch} has no commits that main lacks; reject it or re-spawn")
            r = git("merge", "--no-edit", "-m", f"Merge main into {branch}", "main", cwd=wt)
            if r.returncode:
                git("merge", "--abort", cwd=wt)
                raise ValueError("main does not merge cleanly into the branch. Redo it on the new main, or ask the "
                                 "worker to resolve it: " + (r.stdout + r.stderr)[-400:])
        changed = git("diff", "--name-only", "main...HEAD", cwd=wt).stdout.split()
        if bad := [f for f in changed if f in protected]:
            raise ValueError(f"the branch changes protected swarm guardrail files {bad}; reject it (only the user changes these)")
        checks = _checks_for(changed)
        for c in checks:
            t = subprocess.run(c, cwd=wt, capture_output=True, text=True, encoding="utf-8", errors="replace",
                               stdin=subprocess.DEVNULL, timeout=timeout, env=env)
            if t.returncode:
                raise MergeRed(" ".join(c[-2:]), f"tests failed on the merged branch ({' '.join(c[-2:])}); main is "
                               f"untouched. Send it back to a worker or reject it. Tail:\n" + (t.stdout + t.stderr)[-1500:])
        with file_lock("git"):
            clear_generated_uids(branch)
            ff = git("merge", "--ff-only", branch)
            if ff.returncode:
                if git("merge-base", "--is-ancestor", "HEAD", branch).returncode:
                    continue  # main moved while we tested: merge it in and test again
                raise ValueError("fast-forward of main failed (uncommitted changes in the main checkout?): "
                                 + (ff.stdout + ff.stderr)[-400:])
            p = git("push", "-q", "origin", "HEAD")
            git("worktree", "remove", "--force", str(wt))
            git("branch", "-D", branch)
        if any(c[-2:] == ["godot", "check"] for c in checks):
            refresh_import(env, timeout)
        return [" ".join(c[-2:]) for c in checks], ("" if not p.returncode else p.stderr[-200:])
    raise ValueError("main kept moving during the tests; run the merge again")


def clear_generated_uids(branch: str, root: Path = ROOT) -> list[str]:
    """Delete untracked Godot `.uid` files in the main checkout that `branch` adds. Godot writes them on import
    (refresh_import, an open editor), so a branch that commits the same file would otherwise fail the fast-forward
    ("untracked working tree files would be overwritten"). They are generated, so the branch's copy wins."""
    added = git("diff", "--name-only", "--diff-filter=A", "HEAD", branch, cwd=root).stdout.split()
    untracked = set(git("ls-files", "--others", "--", *[f for f in added if f.endswith(".uid")], cwd=root).stdout.split()) \
        if any(f.endswith(".uid") for f in added) else set()
    for f in untracked:
        (root / f).unlink(missing_ok=True)
    return sorted(untracked)


def refresh_import(env: dict[str, str], timeout: int) -> None:
    """Re-import the main checkout after a merge fast-forwarded it. Only the worktree was imported by the gate, so a
    class_name or asset the merge added is missing from main's .godot cache until something imports it: the game
    run from this checkout then fails to compile scripts that use it (a skirmish wouldn't start). Best effort."""
    try:
        r = subprocess.run(["uv", "run", "--project", "harness", "--quiet", "hx", "godot", "check"], cwd=ROOT,
                           capture_output=True, text=True, encoding="utf-8", errors="replace",
                           stdin=subprocess.DEVNULL, timeout=timeout, env=env)
        if r.returncode:
            event("import_failed", tail=(r.stdout + r.stderr)[-300:])
    except (OSError, subprocess.TimeoutExpired) as e:
        event("import_failed", tail=str(e)[-300:])


def merge_worker(bead: str) -> str:
    """Bring main into the worker branch, run the tests there, then fast-forward main. Main never goes red."""
    j = load_job(bead)
    if not j or j["status"] not in ("done", "partial"):
        raise ValueError(f"{bead}: no finished worker to merge (status {j and j['status']})")
    commit_docs("swarm: docs before merge")
    try:
        names, push_err = merge_branch(j["branch"], Path(j["worktree"]), cfg()["merge"]["test_timeout_s"], PROTECTED)
    except MergeRed as e:
        event("merge_red", bead=bead, check=e.check)
        raise
    j.update(status="merged", merged=now().isoformat(timespec="seconds"), checks=names)
    save_job(j)
    event("merge", bead=bead, pushed=not push_err, checks=names)
    # the work is on main: close the bead here, so a turn killed right after a merge leaves nothing open (sw-0zi.3)
    _bd("close", bead, f"--reason=merged to main by hx swarm merge ({', '.join(names) or 'docs only'} green)")
    return f"merged ({', '.join(names) or 'docs only, no tests'} green)" + (f"; push failed: {push_err}" if push_err else "")


def ask(question: str, sender: str) -> None:
    _append(DOCS / "questions.md", f"\n## {clock.stamp()} from {sender}\n{question.strip()}\n")
    send_mail("designers", sender, f"QUESTION (answer it with `hx swarm mail {sender} \"...\"`):\n{question}")


def reject_worker(bead: str, reason: str) -> str:
    j = load_job(bead)
    if not j:
        raise ValueError(f"no worker job for {bead}")
    with file_lock("git"):
        git("worktree", "remove", "--force", j["worktree"])
        git("branch", "-D", j["branch"])
    j.update(status="rejected", reason=reason, rejected=now().isoformat(timespec="seconds"))
    save_job(j)
    event("reject", bead=bead, reason=reason[:300])
    return "rejected"


# ---------------------------------------------------------------- the supervisor's own pipeline steps (sw-0zi.3)

_PATH = re.compile(r"\b((?:src|harness|data|tests|addons|docs)/[\w./-]*\w)")


def bead_paths(text: str) -> set[str]:
    """Repo paths a bead's text names (files or folders), to keep two workers off the same files."""
    return {p.rstrip("/.") for p in _PATH.findall(text or "")}


def _overlaps(a: set[str], b: set[str]) -> bool:
    return any(x == y or x.startswith(y + "/") or y.startswith(x + "/") for x in a for y in b)


def pick_ready(ready: list[dict], open_beads: list[dict], busy_texts: list[str], c: dict, skip: set[str] = frozenset()) -> dict | None:
    """The next bead the supervisor may spawn on its own, or None. `ready`: `bd ready --json`.
    `open_beads`: every non-closed bead (to find parents with open children). `busy_texts`: bead texts of
    queued and running workers (their named paths must not overlap). `skip`: beads with a worker job.

    Skips epics, parents with open children, beads flagged for a human, the excluded labels (by default
    `swarm-harness`: guardrail work the swarm may not do) and parents (the design-interview epic), and
    design interviews. Order: priority, bugs first, designer-accepted proposals, then oldest."""
    w = c.get("workers", {})
    bad_labels = set(w.get("refill_exclude_labels", ["needs-human", "swarm-harness"]))
    bad_parents = set(w.get("refill_exclude_parents", ["sw-p2q"]))
    parents = {b.get("parent") for b in open_beads if b.get("parent")}
    busy = set().union(*(bead_paths(t) for t in busy_texts)) if busy_texts else set()

    def ok(b: dict) -> bool:
        labels = set(b.get("labels") or [])
        return (b.get("issue_type") != "epic" and b["id"] not in parents and b["id"] not in skip
                and not labels & bad_labels and b.get("parent") not in bad_parents
                and not b.get("title", "").lower().startswith("design interview")
                and not _overlaps(bead_paths(f"{b.get('title', '')}\n{b.get('description', '')}"), busy))

    def key(b: dict) -> tuple:
        return (b.get("priority", 4), b.get("issue_type") != "bug", "swarm-proposed" not in (b.get("labels") or []),
                b.get("created_at", ""))
    cands = sorted((b for b in ready if ok(b)), key=key)
    return cands[0] if cands else None


def _bd_json(*args: str) -> list[dict]:
    r = subprocess.run(["bd", *args, "--json"], cwd=ROOT, capture_output=True, text=True, encoding="utf-8",
                       errors="replace", stdin=subprocess.DEVNULL, timeout=120)
    if r.returncode:
        raise RuntimeError(f"bd {' '.join(args)}: {r.stderr.strip()[-200:]}")
    return json.loads(r.stdout or "[]")


def _bd(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["bd", *args], cwd=ROOT, capture_output=True, text=True, encoding="utf-8",
                          errors="replace", stdin=subprocess.DEVNULL, timeout=120)


# ---------------------------------------------------------------- research jobs

def queue_research(topic: str, requester: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", topic.lower()).strip("-")[:60] or "topic"
    d = STATE / "research"
    open_jobs = [p for p in d.glob("*.json") if json.loads(p.read_text(encoding="utf-8"))["status"] in ("queued", "running")] if d.exists() else []
    if len(open_jobs) >= cfg()["research"]["max_queued"]:
        raise ValueError(f"{len(open_jobs)} research jobs already queued; wait for them")
    if (DOCS / "research" / "reports" / f"{slug}.md").exists():
        raise ValueError(f"a report on {slug} already exists: docs/swarm/research/reports/{slug}.md")
    _write(d / f"{slug}.json", json.dumps({"slug": slug, "topic": topic, "requester": requester, "status": "queued",
                                           "created": now().isoformat(timespec="seconds")}))
    event("research_queued", slug=slug, requester=requester)
    return slug


# ---------------------------------------------------------------- usage digest (auditor input)

def _gateway_rows(since: datetime) -> list[dict]:
    rows = []
    d = ROOT / "harness" / "data" / "raw" / "gateway"
    for day in {since.date(), now().date()}:
        f = d / f"{day:%Y-%m-%d}.jsonl"
        if f.exists():
            for line in f.read_text(encoding="utf-8").splitlines():
                try:
                    r = json.loads(line)
                    if datetime.fromisoformat(r["ts"]) >= since:
                        rows.append(r)
                except (ValueError, KeyError):
                    pass
    return rows


def _delegate_rows(since: datetime) -> list[dict]:
    rows = []
    d = ROOT / "harness" / "data" / "raw" / "delegate"
    for day in {since.date(), now().date()}:
        f = d / f"{day:%Y%m%d}.jsonl"
        if f.exists():
            for line in f.read_text(encoding="utf-8").splitlines():
                try:
                    r = json.loads(line)
                    if datetime.fromisoformat(r["ts"]) >= since:
                        rows.append(r)
                except (ValueError, KeyError):
                    pass
    return rows


def _claude_activity(since: datetime) -> list[dict]:
    """Claude Code transcripts for this project with assistant turns since `since` (model, turns, tokens)."""
    proj = Path.home() / ".claude" / "projects"
    out = []
    if not proj.exists():
        return out
    key = re.sub(r"[^A-Za-z0-9]", "-", str(ROOT))
    for d in proj.iterdir():
        if not d.name.lower().startswith(key.lower()[:30]):
            continue
        for f in d.glob("*.jsonl"):
            if datetime.fromtimestamp(f.stat().st_mtime, timezone.utc) < since:
                continue
            models: dict[str, list[int]] = {}
            for line in f.read_text(encoding="utf-8", errors="replace").splitlines():
                if '"assistant"' not in line:
                    continue
                try:
                    e = json.loads(line)
                    if e.get("type") != "assistant" or datetime.fromisoformat(e["timestamp"].replace("Z", "+00:00")) < since:
                        continue
                    m = e["message"]
                    u = m.get("usage") or {}
                    acc = models.setdefault(m.get("model", "?"), [0, 0])
                    acc[0] += 1
                    acc[1] += int(u.get("output_tokens") or 0)
                except (ValueError, KeyError, TypeError):
                    pass
            for m, (turns, out_tok) in models.items():
                out.append({"session": f.stem[:8], "model": m, "turns": turns, "output_tokens": out_tok})
    return out


def usage(minutes: int = 30) -> dict:
    since = now() - timedelta(minutes=minutes)
    gw: dict[tuple, dict] = {}
    for r in _gateway_rows(since):
        k = (r.get("caller") or "-", r.get("model_group") or r.get("model"), r.get("status"))
        a = gw.setdefault(k, {"caller": k[0], "model": k[1], "status": k[2], "calls": 0, "prompt_tokens": 0,
                              "completion_tokens": 0, "cost_usd": 0.0, "rate_limited": 0})
        a["calls"] += 1
        a["prompt_tokens"] += r.get("prompt_tokens") or 0
        a["completion_tokens"] += r.get("completion_tokens") or 0
        a["cost_usd"] += r.get("cost_usd") or 0.0
        a["rate_limited"] += "RateLimit" in (r.get("error") or "")
    banners: dict[str, int] = {}
    for f in (STATE / "logs").glob("*/*.log") if (STATE / "logs").exists() else []:
        if datetime.fromtimestamp(f.stat().st_mtime, timezone.utc) < since:
            continue
        for m in re.findall(r"^> \S+ · (\S+)", f.read_text(encoding="utf-8", errors="replace"), re.M):
            banners[m] = banners.get(m, 0) + 1
    ev = events(since)
    return {
        "window_minutes": minutes, "since": since.isoformat(timespec="seconds"),
        "gateway_calls": sorted(gw.values(), key=lambda a: -a["calls"]),
        "swarm_log_model_banners": banners,
        "hx_delegate_calls": [{"model": r.get("model"), "target": r.get("target"), "level": r.get("level")} for r in _delegate_rows(since)],
        "claude_code_activity": _claude_activity(since),
        "swarm_events": {k: sum(e["kind"] == k for e in ev) for k in sorted({e["kind"] for e in ev})},
        "turn_failures": [e for e in ev if e["kind"] == "turn" and e.get("rc") not in (0, None)][-10:],
        "workers": [{k: j.get(k) for k in ("bead", "status", "attempts", "created")} for j in jobs() if j["status"] not in DONE],
        "commits_on_main": git("log", f"--since={since.isoformat()}", "--format=%h %an %s", "-n", "30").stdout.splitlines(),
    }


def selfcheck() -> dict:
    conf = json.loads(OC_CONFIG.read_text(encoding="utf-8"))
    models = [f"hx/{m}" for m in conf["provider"]["hx"]["models"]]
    u = usage(30)
    non_qwen_swarm = [g for g in u["gateway_calls"] if str(g["caller"]).startswith("swarm") and g["model"] != GATEWAY_MODEL]
    s = load_state()
    alive = supervisor_pid() is not None
    return {"opencode_models": models, "config_ok": models == [MODEL] and conf.get("model") == MODEL,
            "non_qwen_swarm_calls_30m": non_qwen_swarm, "log_banners_30m": u["swarm_log_model_banners"],
            "supervisor_alive": alive, "generation": s["generation"], "alert_streak": s["alert_streak"],
            "open_workers": u["workers"], "events_30m": u["swarm_events"]}


# ---------------------------------------------------------------- running one agent turn

def gateway_up() -> bool:
    try:
        with urllib.request.urlopen("http://127.0.0.1:4000/health/liveliness", timeout=5):
            return True
    except OSError:
        return False


def ensure_gateway() -> None:
    if not gateway_up():
        log("gateway down; starting it")
        subprocess.run([sys.executable, "-m", "hx.cli", "gateway", "start"], cwd=ROOT / "harness",
                       env=dict(os.environ, PYTHONPATH=str(ROOT / "harness" / "src")), capture_output=True, timeout=180)


def opencode_exe() -> str:
    from hx import providers
    exe = providers.find_cli(providers.load()["opencode-zen"])
    if not exe:
        raise RuntimeError("opencode CLI not found")
    return exe


def _tail(path: Path, n: int) -> str:
    if not path.exists():
        return "(none yet)"
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    return "\n".join(lines[-n:]) or "(empty)"


def compose(role: str, role_files: str | list[str], extra: str = "", inbox: str | None = None) -> str:
    c = cfg()
    s = load_state()
    common = (ROLES / "_common.md").read_text(encoding="utf-8")
    files = [role_files] if isinstance(role_files, str) else role_files
    body = "\n\n".join((ROLES / f"{f}.md").read_text(encoding="utf-8") for f in files)
    mail = take_mail(role) if inbox is None else inbox
    status = (DOCS / "STATUS.md").read_text(encoding="utf-8") if (DOCS / "STATUS.md").exists() else "(no status yet)"
    ctx = (f"# Run context (generated by the supervisor)\n"
           f"- You are: **{role}**. Generation {s['generation']}. Time now: {clock.stamp()}. "
           f"The run ends {c['run']['end_at']}.\n"
           f"- Repo (main checkout): `{ROOT.as_posix()}`. Your journal: `docs/swarm/journals/{role}.md`.\n\n"
           f"## Your inbox (new since your last turn)\n{mail or '(empty)'}\n\n"
           f"## Your journal (last 40 lines)\n{_tail(DOCS / 'journals' / f'{role}.md', 40)}\n\n"
           f"## Swarm status\n{status.split(STATUS_DETAILS)[0].strip()[:3000]}\n")
    return f"{common}\n\n{body}\n\n{ctx}\n{extra}".strip() + "\n"


# ---------------------------------------------------------------- turn budgets and kill stubs (sw-0zi.5)

def seconds_per_call(rows: list[dict]) -> float | None:
    """What one successful model call costs an agent right now: the median latency of the last hour's
    successful swarm calls, scaled up by the share of rate-limited attempts (each is retried). None
    with fewer than 5 successful calls (no evidence: keep the configured limits)."""
    swarm_rows = [r for r in rows if str(r.get("caller") or "").startswith("swarm")]
    ok = sorted(r["latency_s"] for r in swarm_rows if r.get("status") == "success" and isinstance(r.get("latency_s"), (int, float)))
    if len(ok) < 5:
        return None
    limited = sum("RateLimit" in (r.get("error") or "") for r in swarm_rows)
    return ok[len(ok) // 2] * (1 + limited / len(swarm_rows))


def turn_budget(c: dict, group: str, base_timeout: int, per_call: float | None) -> tuple[int, int]:
    """(time limit in seconds, call budget) for a turn. The limit covers the role's call budget at the
    current cost per call with some slack, never below the configured limit (a fast gateway changes
    nothing) and never above budgets.cap_factor times it. On 2026-11-21 a 60 min turn at ~4 min a call
    got ~12 calls and died before it journaled."""
    b = c.get("budgets", {})
    calls = int(b.get(group, b.get("default", 20)))
    if per_call is None:
        return base_timeout, calls
    want = calls * per_call * float(b.get("slack", 1.3))
    return int(min(max(want, base_timeout), base_timeout * float(b.get("cap_factor", 2.0)))), calls


_ACTION = re.compile(r"^(?:\$|→|←|✱|⚙|%) .+")
_ANSI = re.compile(r"\x1b\[[0-9;]*m")


def turn_stub(text: str, commits: list[str], rc: int, seconds: int, now_: datetime | None = None) -> str:
    """The journal entry the supervisor writes for a turn it had to end, so the next turn knows where it
    stopped: the last actions from the turn log and the commits it made."""
    lines = [_ANSI.sub("", ln).strip() for ln in text.splitlines()]
    actions = [ln[:160] for ln in lines if _ACTION.match(ln)][-8:]
    what = "killed at its time limit" if rc == -9 else "ended because the swarm stopped"
    out = [f"## {clock.stamp(now_ or now())} turn {what} after {seconds // 60} min (supervisor note)",
           "- last actions:" if actions else "- last actions: none recorded"]
    out += [f"  - `{a}`" for a in actions]
    out.append("- commits this turn: " + ("; ".join(commits[:8]) if commits else "none"))
    out.append("- next: check what the last actions finished (files, beads, merges) before repeating them; "
               "journal and commit earlier this time.")
    return "\n".join(out) + "\n"


# Turns in flight (pid -> Popen), so stopping the supervisor can end them instead of orphaning them (sw-0zi.11).
_running: dict[int, subprocess.Popen] = {}
_running_lock = threading.Lock()
_stopping = threading.Event()
STOPPED = -15  # rc of a turn ended because the swarm stopped


def stop_turns() -> list[int]:
    """Ends every running turn (each waiting run_turn returns STOPPED). Returns the pids it killed."""
    _stopping.set()
    with _running_lock:
        procs = list(_running.values())
    for p in procs:
        if p.poll() is None:
            background.kill_tree(p.pid)
    return [p.pid for p in procs]


def run_turn(role: str, prompt: str, cwd: Path = ROOT, timeout: int = 1800, kind: str = "turn") -> tuple[int, str]:
    ensure_gateway()
    from hx import keystore
    env = dict(os.environ, OPENCODE_CONFIG=str(OC_CONFIG), HX_GATEWAY_KEY=keystore.get("HX_GATEWAY_KEY") or "",
               HX_SWARM="1", HX_SWARM_ROLE=role, PYTHONUTF8="1")
    env.pop("HX_REPO_ROOT", None)
    logf = STATE / "logs" / role / f"{stamp()}.log"
    logf.parent.mkdir(parents=True, exist_ok=True)
    _write(logf.with_suffix(".prompt.md"), prompt)
    t0 = time.time()
    with logf.open("w", encoding="utf-8") as out:
        kw = {"creationflags": subprocess.CREATE_NO_WINDOW} if sys.platform == "win32" else {}
        p = subprocess.Popen([opencode_exe(), "run", "--standalone", "--auto", "-m", MODEL, "--title", f"swarm {role}",
                              "--file", str(logf.with_suffix(".prompt.md")),
                              f"Follow the attached instructions as the {role}. Start now."],
                             cwd=cwd, env=env, stdout=out, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, **kw)
        with _running_lock:
            _running[p.pid] = p
        try:
            deadline = t0 + timeout
            rc = None
            while rc is None:
                if _stopping.is_set():
                    background.kill_tree(p.pid)
                    p.wait(30)
                    rc = STOPPED
                    break
                try:
                    rc = p.wait(timeout=max(0.1, min(2.0, deadline - time.time())))
                except subprocess.TimeoutExpired:
                    if time.time() >= deadline:
                        background.kill_tree(p.pid)
                        rc = -9
            if rc not in (0, -9) and _stopping.is_set():  # killed by stop_turns() while we waited
                rc = STOPPED
        finally:
            with _running_lock:
                _running.pop(p.pid, None)
    dur = round(time.time() - t0)
    text = logf.read_text(encoding="utf-8", errors="replace")
    rate_limited = text.count("rate limit") + text.count("RateLimit")
    extra = {"stopped": True} if rc == STOPPED else {}
    event(kind, role=role, rc=rc, seconds=dur, rate_limited=rate_limited, log=str(logf.relative_to(STATE)), **extra)
    if rc in (-9, STOPPED):  # the turn could not journal: leave the next one a trace (sw-0zi.5)
        try:
            since = datetime.fromtimestamp(t0, timezone.utc).isoformat(timespec="seconds")
            commits = git("log", f"--since={since}", "--format=%h %s", "-n", "8", cwd=cwd).stdout.splitlines()
            _append(DOCS / "journals" / f"{role}.md", "\n" + turn_stub(text, commits, rc, dur))
        except Exception as e:  # noqa: BLE001 - a missing stub must never break the loop
            log(f"turn stub for {role}: {e!r}")
    update_state(lambda s: s["turns"].__setitem__(role, s["turns"].get(role, 0) + 1))
    return rc, text


# ---------------------------------------------------------------- the audit rules (sw-0zi.4)

SEVERITY = {"PASS": 0, "WARN": 1, "FAIL": 2}
OK_BANNERS = {GATEWAY_MODEL, MODEL}


def _since(e: dict | str, t: datetime) -> float:
    """Minutes from an event's timestamp (or an ISO timestamp string) to t."""
    return (t - datetime.fromisoformat(e if isinstance(e, str) else e["ts"])).total_seconds() / 60


def rule_verdict(c: dict, u: dict, ev: list[dict], js: list[dict], t: datetime, *, ready: int | None = None,
                 paused: bool = False, orch_last: datetime | None = None) -> dict:
    """The compliance and health verdict from counts alone, no model (sw-0zi.4).

    `u`: usage(window) digest. `ev`: events of the last few hours. `js`: open worker jobs. `ready`: ready
    beads (None if unknown). `paused`: the orchestrator is paused for a postmortem. `orch_last`: when the
    orchestrator last started or finished a turn.

    Returns {"verdict", "reason", "fail": [...], "act": [...], "health": [...]}: FAIL findings break the
    hard rules; `act` are WARNs the orchestrator can act on (mailed); `health` are WARNs it can't fix
    (throttling, slow turns), shown on STATUS.md only.
    """
    a = c.get("audit", {})
    fail, act, health = [], [], []
    swarm_calls = [g for g in u.get("gateway_calls", []) if str(g.get("caller", "")).startswith("swarm")]
    # Compliance: model, money.
    for g in swarm_calls:
        if g.get("model") != GATEWAY_MODEL:
            fail.append(f"non-Qwen model {g.get('model')} used by {g['caller']} ({g.get('calls', 0)} calls)")
    bad = {m: n for m, n in u.get("swarm_log_model_banners", {}).items() if m not in OK_BANNERS}
    if bad:
        fail.append(f"non-Qwen model banners in swarm logs: {bad}")
    cost = sum(g.get("cost_usd") or 0 for g in swarm_calls)
    if cost > 0:
        fail.append(f"swarm calls cost {cost:.4f} USD (must be 0)")
    # The orchestrator is alive and doing something.
    o = c.get("orchestrator", {})
    # a turn, its gap with backoff, then up to a heartbeat of waiting for mail (sw-0zi.3)
    silent = a.get("orchestrator_silent_min",
                   (o.get("turn_timeout_s", 3600) + o.get("pause_s", 240) + o.get("heartbeat_s", 3600)) / 60 + 45)
    if not paused and orch_last is not None and (t - orch_last).total_seconds() / 60 > silent:
        fail.append(f"no orchestrator turn for {(t - orch_last).total_seconds() / 60:.0f} min (limit {silent:.0f})")
    loop_min = a.get("loop_window_min", 120)
    recent = [e for e in ev if _since(e, t) <= loop_min]
    orch_turns = sum(e["kind"] == "turn" and e.get("role") == "orchestrator" for e in recent)
    moves = sum(e["kind"] in ("spawn", "merge", "reject", "research_queued") for e in recent)
    busy = any(j["status"] in ("queued", "running") for j in js)
    if not paused and orch_turns >= a.get("loop_turns", 4) and not moves and not busy and ready:
        fail.append(f"orchestrator looping: {orch_turns} turns in {loop_min} min, no spawn/merge/reject, "
                    f"workers idle, {ready} beads ready")
    # Things the orchestrator can act on.
    wait = a.get("review_wait_min", 60)
    for j in js:
        if j["status"] in ("done", "partial", "failed") and j.get("finished") and _since(j["finished"], t) > wait:
            act.append(f"{j['bead']} finished ({j['status']}) {_since(j['finished'], t):.0f} min ago and awaits review")
        if j["status"] == "running" and j.get("started"):
            limit = c.get("workers", {}).get("timeout_s", 7200) / 60 + 10
            if _since(j["started"], t) > limit:
                act.append(f"worker {j['bead']} has run {_since(j['started'], t):.0f} min, past its {limit:.0f} min limit")
    reds: dict[str, int] = {}
    for e in ev:
        if e["kind"] == "merge_red" and _since(e, t) <= 180:
            reds[e["bead"]] = reds.get(e["bead"], 0) + 1
    act += [f"{b} failed the merge gate {n} times in 3 h" for b, n in sorted(reds.items()) if n >= 2]
    # Health the orchestrator can't fix.
    calls = sum(g.get("calls", 0) for g in swarm_calls)
    limited = sum(g.get("rate_limited", 0) for g in swarm_calls)
    if calls >= 10 and limited / calls > a.get("rate_limited_warn", 0.4):
        health.append(f"{limited}/{calls} calls rate-limited ({100 * limited / calls:.0f}%)")
    window = [e for e in ev if _since(e, t) <= u.get("window_minutes", 30)]
    turns = [e for e in window if e["kind"] in ("turn", "worker", "audit", "research")]
    failed = [e for e in turns if e.get("rc") not in (0, None)]
    if len(turns) >= 4 and len(failed) / len(turns) > 0.5:
        health.append(f"{len(failed)}/{len(turns)} turns failed or timed out")
    two_h = [e for e in ev if _since(e, t) <= 120]
    if any(e["kind"] == "worker" for e in two_h) and not any(e["kind"] == "merge" for e in two_h):
        health.append("no merge in 2 h while workers ran")
    verdict = "FAIL" if fail else "WARN" if act or health else "PASS"
    head = (f"{calls} swarm calls ({limited} rate-limited), all {GATEWAY_MODEL}, cost 0 USD"
            if not fail else "; ".join(fail))
    parts = [head] + [f"act: {x}" for x in act] + [f"health: {x}" for x in health]
    return {"verdict": verdict, "reason": " | ".join(parts), "fail": fail, "act": act, "health": health}


def _ready_count() -> int | None:
    try:
        r = subprocess.run(["bd", "ready", "--json"], cwd=ROOT, capture_output=True, text=True, timeout=60, encoding="utf-8")
        return len(json.loads(r.stdout)) if r.returncode == 0 else None
    except (OSError, ValueError, subprocess.SubprocessError):
        return None


def _orchestrator_last() -> datetime | None:
    """Start of the newest orchestrator turn log, or the last orchestrator turn event, whichever is later."""
    last = None
    d = STATE / "logs" / "orchestrator"
    for f in d.glob("*.log") if d.exists() else []:
        try:
            ts = datetime.strptime(f.stem, "%Y%m%dT%H%M%SZ").replace(tzinfo=timezone.utc)
        except ValueError:
            continue
        last = ts if last is None or ts > last else last
    for e in events(now() - timedelta(days=1)):
        if e["kind"] == "turn" and e.get("role") == "orchestrator":
            ts = datetime.fromisoformat(e["ts"])
            last = ts if last is None or ts > last else last
    return last


# ---------------------------------------------------------------- supervisor

def supervisor_pid() -> int | None:
    f = STATE / "supervisor.pid"
    if not f.exists():
        return None
    pid = int(f.read_text().strip() or 0)
    if sys.platform == "win32":
        r = subprocess.run(["tasklist", "/FI", f"PID eq {pid}", "/NH"], capture_output=True, text=True)
        return pid if str(pid) in r.stdout else None
    try:
        os.kill(pid, 0)
        return pid
    except OSError:
        return None


class Slots:
    """A turn pool whose size can change while turns hold slots: shrinking never interrupts a running
    turn, it only makes new turns wait until enough slots are free."""

    def __init__(self, size: int) -> None:
        self.size, self.used = size, 0
        self.cond = threading.Condition()

    def resize(self, size: int) -> None:
        with self.cond:
            self.size = size
            self.cond.notify_all()

    def __enter__(self) -> Slots:
        with self.cond:
            while self.used >= self.size:
                self.cond.wait(5)
            self.used += 1
        return self

    def __exit__(self, *exc) -> None:
        with self.cond:
            self.used -= 1
            self.cond.notify_all()


class Supervisor:
    def __init__(self) -> None:
        self.c = cfg()
        self.cfg_mtime = cfg_mtime()
        self.stop = threading.Event()
        self.orch_paused = threading.Event()   # set while a postmortem runs
        self.orch_running = threading.Event()  # set while an orchestrator turn runs
        self.pools = {p: Slots(self.c["run"][f"{p}_slots"]) for p in ("core", "support")}
        self.end = datetime.fromisoformat(self.c["run"]["end_at"])
        self.workers_started = 0
        self.worker_threads: list[threading.Thread] = []

    def maybe_reload(self) -> list[str] | None:
        """Re-reads swarm.toml when its mtime changed (sw-0zi.1). Loops read `self.c` on every use, so a
        change applies from the next turn or wait; turn pools resize without touching running turns, and a
        larger workers.max_parallel starts more worker threads. A file that fails to parse is logged once and
        ignored (the old config stays). Returns the changed keys, or None when nothing was applied."""
        m = cfg_mtime()
        if m == self.cfg_mtime:
            return None
        self.cfg_mtime = m
        try:
            new = cfg()
            for p in self.pools:
                int(new["run"][f"{p}_slots"])
            end = datetime.fromisoformat(new["run"]["end_at"])
        except (OSError, ValueError, KeyError, TypeError, tomllib.TOMLDecodeError) as e:
            log(f"swarm.toml not reloaded (kept the running config): {e!r}")
            event("config_error", error=repr(e)[:300])
            return None
        changed = cfg_diff(self.c, new)
        if not changed:
            return None
        self.c = new
        self.end = end
        for p, s in self.pools.items():
            s.resize(int(new["run"][f"{p}_slots"]))
        log(f"swarm.toml reloaded: {', '.join(changed)}")
        event("config_reloaded", changed=changed)
        self.start_workers()
        return changed

    def start_workers(self) -> None:
        """Starts worker threads up to workers.max_parallel (threads above the limit idle in worker_loop)."""
        while self.workers_started < int(self.c["workers"]["max_parallel"]):
            n = self.workers_started
            t = threading.Thread(target=self._guard, args=(lambda n=n: self.worker_loop(n),), name=f"worker{n}", daemon=True)
            self.workers_started += 1
            self.worker_threads.append(t)
            t.start()

    def alive(self) -> bool:
        if (STATE / "STOP").exists():
            self.stop.set()
        if now() >= self.end:
            self.stop.set()
        return not self.stop.is_set()

    def wait(self, seconds: float) -> None:
        end = time.time() + seconds
        while time.time() < end and self.alive():
            time.sleep(min(5, max(0.1, end - time.time())))

    def support_paused(self) -> bool:
        """True while the gateway is throttling (sw-0zi.2): support turns (designers, researchers, research,
        retro) wait so the few calls that start go to workers and the orchestrator. On when, over the last
        hour of swarm calls (at least 10), the rate-limited share exceeds run.throttle_share_on or successful
        calls fall below run.throttle_min_ok_per_h; off once the share is under run.throttle_share_off and
        successes are back above the minimum. Evaluated at most once a minute; logs throttle_on/off events."""
        t = time.time()
        if t - getattr(self, "_throttle_checked", 0.0) < 60:
            return getattr(self, "throttled", False)
        self._throttle_checked = t
        r = self.c.get("run", {})
        rows = [x for x in _gateway_rows(now() - timedelta(hours=1)) if str(x.get("caller") or "").startswith("swarm")]
        limited = sum("RateLimit" in (x.get("error") or "") for x in rows)
        ok = sum(x.get("status") == "success" for x in rows)
        share = limited / len(rows) if rows else 0.0
        was = getattr(self, "throttled", False)
        if len(rows) < 10:  # too little traffic to call it throttling
            on = False
        elif was:
            on = not (share < r.get("throttle_share_off", 0.25) and ok >= r.get("throttle_min_ok_per_h", 30))
        else:
            on = share > r.get("throttle_share_on", 0.4) or ok < r.get("throttle_min_ok_per_h", 30)
        if on != was:
            self.throttled = on
            event("throttle_on" if on else "throttle_off", calls=len(rows), ok=ok, rate_limited=limited)
            log(f"gateway {'throttled: support turns paused' if on else 'recovered: support turns resume'} "
                f"({ok} ok, {limited} rate-limited of {len(rows)} swarm calls in the last hour)")
        return on

    def hold_support(self) -> None:
        """Waits (in 5 min steps) while support turns are paused for throttling."""
        while self.alive() and self.support_paused():
            self.wait(300)

    def backoff(self) -> float:
        """Seconds to add between turns when Nous is rate-limiting (share of 429s in the last 10 min)."""
        rows = _gateway_rows(now() - timedelta(minutes=10))
        if len(rows) < 10:
            return 0
        share = sum("RateLimit" in (r.get("error") or "") for r in rows) / len(rows)
        return 0 if share < 0.2 else min(900, 60 + 1200 * share)

    def budgeted(self, group: str, prompt: str, base_timeout: int) -> tuple[str, int]:
        """The turn's time limit from the current cost of a call (turn_budget), and the prompt with its
        budget stated, so the agent can pace itself (sw-0zi.5). Cost per call is re-measured once a minute."""
        t = time.time()
        if t - getattr(self, "_per_call_at", 0.0) >= 60:
            self._per_call_at = t
            self._per_call = seconds_per_call(_gateway_rows(now() - timedelta(hours=1)))
        per_call = getattr(self, "_per_call", None)
        timeout, calls = turn_budget(self.c, group, base_timeout, per_call)
        pace = f" (calls take about {per_call:.0f} s each right now)" if per_call else ""
        note = (f"\n# Your budget this turn\nAbout {calls} model calls; the time limit is {timeout // 60} min{pace}. "
                "Commit and journal after each finished step, and stop starting new work once most of it is used: a "
                "turn killed at the limit loses whatever it had not written down.\n")
        return prompt + note, timeout

    def turn(self, role: str, prompt: str, pool: str = "core", group: str | None = None, **kw) -> tuple[int, str]:
        """core = orchestrator and workers (the code pipeline); support = designers, researchers, research, retro.
        Separate pools so support roles can never take the pipeline's share of the rate-limited model.
        `group` names the call budget (swarm.toml [budgets]) that sets the time limit."""
        with self.pools[pool]:
            if not self.alive():
                return STOPPED, ""
            if group:
                prompt, kw["timeout"] = self.budgeted(group, prompt, kw.get("timeout", 1800))
            return run_turn(role, prompt, **kw)

    # -- loops
    def orchestrator_loop(self) -> None:
        """Event-driven (sw-0zi.3): after a turn and its minimum gap (pause_s, plus backoff), the next turn
        starts only when the orchestrator has mail (a worker finished, an audit alert, a designer's answer)
        or the heartbeat comes due. Polling turns took 38% of all calls on 2026-11-21."""
        fails = 0
        why = "the swarm started"
        while self.alive():
            if self.orch_paused.is_set():
                self.wait(30)
                continue
            extra = f"# Why you were woken\n{why}.\n"
            self.orch_running.set()
            try:
                rc, _ = self.turn("orchestrator", compose("orchestrator", "orchestrator", extra), group="orchestrator",
                                  timeout=self.c["orchestrator"]["turn_timeout_s"])
            finally:
                self.orch_running.clear()
            fails = fails + 1 if rc not in (0, STOPPED) else 0
            self.wait(self.c["orchestrator"]["pause_s"] + self.backoff() + min(1800, 60 * 2 ** fails if fails else 0))
            why = self.wait_for_orchestrator_work()

    def wait_for_orchestrator_work(self) -> str:
        """Blocks until the orchestrator's inbox has mail or the heartbeat is due; returns why."""
        t0 = time.time()
        while self.alive():
            n = inbox_count("orchestrator")
            if n:
                return f"{n} new message(s) in your inbox"
            if time.time() - t0 >= self.c["orchestrator"].get("heartbeat_s", 3600):
                return "the hourly heartbeat (no new mail): check the workers and fill empty slots"
            self.wait(15)
        return "the swarm is stopping"

    def pipeline_loop(self) -> None:
        """The supervisor's own pipeline steps, once a minute: merge finished workers nobody reviewed in
        time, and keep worker slots filled when the orchestrator has not (sw-0zi.3)."""
        self.wait(60)
        while self.alive():
            for step in (self.auto_merge, self.refill):
                try:
                    step()
                except Exception as e:  # noqa: BLE001 - one bad step must not stop the other
                    log(f"pipeline {step.__name__}: {e!r}")
            self.wait(60)

    def refill(self) -> str | None:
        """Spawns the next ready bead when a worker slot has been free for workers.refill_idle_min minutes (so
        the orchestrator gets the first pick after a worker finishes). Returns the bead spawned, or None."""
        w = self.c["workers"]
        if not w.get("auto_refill", True):
            return None
        js = jobs()
        busy = [j for j in js if j["status"] in ("queued", "running")]
        open_jobs = [j for j in js if j["status"] in ("queued", "running", "done", "partial")]
        if len(busy) >= int(w["max_parallel"]) or len(open_jobs) >= int(w["max_open"]):
            return None
        idle_s = w.get("refill_idle_min", 10) * 60
        last = max((datetime.fromisoformat(e["ts"]) for e in events(now() - timedelta(seconds=idle_s))
                    if e["kind"] in ("spawn", "worker_done", "merge", "reject")), default=None)
        if last is not None:
            return None
        b = pick_ready(_bd_json("ready"), _bd_json("list", "--status=open,in_progress,blocked", "--limit", "0"),
                       [j.get("bead_text", "") for j in busy], self.c, skip={j["bead"] for j in js if j["status"] not in DONE})
        if not b:
            return None
        _bd("update", b["id"], "--claim")
        spawn_worker(b["id"], note="Spawned by the supervisor (auto-refill: a worker slot was idle). Read the bead's "
                                   "acceptance criteria; keep to the files it names.")
        event("auto_spawn", bead=b["id"])
        send_mail("orchestrator", "supervisor", f"Auto-refill: a worker slot was idle for {idle_s // 60} min, so I spawned "
                                                f"{b['id']} ({b.get('title', '')[:80]}), the top ready bead. Re-brief it with "
                                                f"`hx swarm spawn {b['id']} --note ...` after it finishes if needed.")
        return b["id"]

    def auto_merge(self) -> list[str]:
        """Merges `done` workers (a WORKER RESULT, rc 0, no WIP) that waited longer than
        workers.review_timeout_min for the orchestrator. The merge gate still runs the tests and refuses
        guardrail files; a merged bead is labelled swarm-unreviewed for a later look. Each job is tried once."""
        limit = self.c["workers"].get("review_timeout_min", 90)
        merged = []
        if self.orch_running.is_set():  # it may be merging the same bead right now
            return merged
        for j in jobs():
            if (j["status"] != "done" or j.get("auto_merge_tried") or not j.get("finished") or not j.get("commits")
                    or (now() - datetime.fromisoformat(j["finished"])).total_seconds() < limit * 60):
                continue
            j["auto_merge_tried"] = now().isoformat(timespec="seconds")
            save_job(j)
            try:
                out = merge_worker(j["bead"])
            except Exception as e:  # noqa: BLE001 - red tests, conflicts, protected files: leave it to the orchestrator
                event("auto_merge_failed", bead=j["bead"], error=str(e)[:300])
                send_mail("orchestrator", "supervisor", f"Auto-merge of {j['bead']} (unreviewed for {limit} min) failed; "
                                                        f"it is yours to fix, re-spawn or reject:\n{str(e)[:1500]}")
                continue
            _bd("update", j["bead"], "--add-label=swarm-unreviewed",
                f"--append-notes=swarm: auto-merged by the supervisor after {limit} min without review ({out})")
            event("auto_merge", bead=j["bead"])
            send_mail("orchestrator", "supervisor", f"Auto-merged {j['bead']} after {limit} min without review: {out}. "
                                                    "It is labelled swarm-unreviewed; review the diff on main when you can.")
            merged.append(j["bead"])
        return merged

    def worker_loop(self, n: int) -> None:
        while self.alive():
            if n >= int(self.c["workers"]["max_parallel"]):  # lowered by a config reload: idle until raised again
                self.wait(20)
                continue
            queued = []
            with file_lock("jobs"):
                for j in jobs():
                    if j["status"] == "queued":
                        j.update(status="running", started=now().isoformat(timespec="seconds"), runner=n)
                        save_job(j)
                        queued.append(j)
                        break
            if not queued:
                self.wait(20)
                continue
            j = queued[0]
            extra = (f"# Your assignment\nBead `{j['bead']}` (attempt {j['attempts']}). Worktree: `{j['worktree']}` on branch "
                     f"`{j['branch']}` (based on `{j['base'][:9]}`). Orchestrator's note: {j.get('note') or '-'}\n\n"
                     f"```\n{j['bead_text']}\n```\n")
            rc, text = self.turn(f"worker-{j['bead']}", compose("worker", "worker", extra, inbox=""),
                                 cwd=Path(j["worktree"]), timeout=self.c["workers"]["timeout_s"], kind="worker", group="worker")
            wip = save_wip(Path(j["worktree"]), f"worker turn ended (rc={rc}) with uncommitted changes")
            ahead = int(git("rev-list", "--count", f"main..{j['branch']}").stdout.strip() or 0)
            if rc == STOPPED:  # the swarm is stopping: back in the queue, so the next start resumes it on its branch
                j.update(status="queued", rc=rc, commits=ahead)
                save_job(j)
                event("worker_done", bead=j["bead"], status="stopped", commits=ahead, rc=rc, wip=wip)
                continue
            m = re.search(r"WORKER RESULT.*", text, re.S)
            summary = m.group(0)[:3500] if m else text[-3500:]
            status = "failed" if not ahead else ("done" if rc == 0 and m and not wip else "partial")
            j.update(status=status, finished=now().isoformat(timespec="seconds"), rc=rc, commits=ahead, summary=summary)
            save_job(j)
            event("worker_done", bead=j["bead"], status=status, commits=ahead, rc=rc, wip=wip)
            why = {"done": "finished", "partial": "was cut off (timeout or error) after committing work; its branch is kept",
                   "failed": "produced no commits"}[status]
            send_mail("orchestrator", "supervisor",
                      f"Worker for {j['bead']} {why}: status **{status}**, {ahead} commit(s) ahead of main, rc={rc}"
                      f"{', unfinished changes saved as a WIP commit' if wip else ''}.\n"
                      f"Review: `git -C {j['worktree']} log --stat main..HEAD`. Then `hx swarm merge {j['bead']}` if it is "
                      f"complete, or `hx swarm spawn {j['bead']} --note \"<what is left>\"` to continue on the same branch, "
                      f"or `hx swarm reject {j['bead']} --reason ...` to discard it.\n\nWorker's report:\n{summary[-1500:]}")
            self.wait(5)

    def periodic_loop(self, group: str) -> None:
        i = 0
        self.wait(self.c[group].get("initial_delay_s", 60))
        while self.alive():
            self.hold_support()
            if not self.alive():
                break
            sec = self.c[group]  # read each round so a config reload applies
            roles = list(sec["roles"])
            role = roles[i % len(roles)]
            self.turn(role, compose(role, [sec["base"], role]), pool="support", timeout=sec["turn_timeout_s"], group=sec["base"])
            i += 1
            self.wait(max(60, sec["every_s"] / len(roles)) + self.backoff())

    def research_loop(self) -> None:
        while self.alive():
            self.hold_support()
            d = STATE / "research"
            job = None
            with file_lock("jobs"):
                for p in sorted(d.glob("*.json")) if d.exists() else []:
                    j = json.loads(p.read_text(encoding="utf-8"))
                    if j["status"] == "queued":
                        j["status"] = "running"
                        _write(p, json.dumps(j))
                        job = (p, j)
                        break
            if not job:
                self.wait(30)
                continue
            p, j = job
            out = DOCS / "research" / "reports" / f"{j['slug']}.md"
            extra = f"# Your assignment\nTopic: {j['topic']}\nRequested by: {j['requester']}\nWrite the report to `{out.relative_to(ROOT).as_posix()}`.\n"
            rc, _ = self.turn(f"research-{j['slug'][:30]}", compose("deep-researcher", "deep-researcher", extra, inbox=""), pool="support",
                              timeout=self.c["research"]["timeout_s"], kind="research", group="research")
            if rc == STOPPED and not out.exists():  # the swarm is stopping: run it again on the next start
                j["status"] = "queued"
                _write(p, json.dumps(j))
                continue
            j.update(status="done" if out.exists() else "failed", finished=now().isoformat(timespec="seconds"))
            _write(p, json.dumps(j))
            send_mail("researchers", "supervisor", f"Deep research `{j['slug']}` finished: {j['status']}. Report: `{out.relative_to(ROOT).as_posix()}`.")
            event("research_done", slug=j["slug"], status=j["status"])

    def audit_loop(self) -> None:
        self.wait(self.c["audit"]["every_s"])
        while self.alive():
            t0 = time.time()
            if not self.orch_paused.is_set():
                self.run_audit()
            self.wait(max(60, self.c["audit"]["every_s"] - (time.time() - t0)))

    def run_audit(self) -> None:
        """One audit cycle (sw-0zi.4). The rules give the verdict every cycle without a model call. The model
        auditor runs only to escalate (a FAIL, something the orchestrator can act on, or a FAIL to confirm)
        or for its periodic narrative report; it may raise the verdict, never lower it, and a killed model
        turn leaves the rules' verdict standing."""
        a = self.c["audit"]
        t0 = now().replace(microsecond=0)  # events are stamped to the second
        u = usage(a["window_min"])
        js = [j for j in jobs() if j["status"] not in DONE]
        rv = rule_verdict(self.c, u, events(t0 - timedelta(hours=6)), js, t0, ready=_ready_count(),
                          paused=self.orch_paused.is_set(), orch_last=_orchestrator_last())
        event("verdict", verdict=rv["verdict"], reason=rv["reason"][:2000], by="rules")
        s = load_state()
        last_model = s.get("last_model_audit")
        since_model = (t0 - datetime.fromisoformat(last_model)).total_seconds() if last_model else float("inf")
        escalate = (rv["verdict"] == "FAIL" or s.get("last_verdict") == "FAIL"
                    or (rv["act"] and since_model >= a.get("model_min_gap_s", 3600))
                    or since_model >= a.get("model_every_s", 14400))
        final = rv
        if rv["verdict"] == "FAIL":  # alert now; the model only writes the report, it can't raise a FAIL
            self.apply_verdict(rv)
        if escalate:
            update_state(lambda s: s.__setitem__("last_model_audit", t0.isoformat(timespec="seconds")))
            why = ("the rules found a FAIL" if rv["verdict"] == "FAIL" else "the last audit was a FAIL: confirm or clear it"
                   if s.get("last_verdict") == "FAIL" else "the rules found something the orchestrator should act on"
                   if rv["act"] else "the periodic report is due")
            digest = json.dumps(u, indent=1)[:20000]
            extra = (f"# Why you were called\n{why}.\n\n# The rules' verdict (already recorded)\n**{rv['verdict']}**: {rv['reason']}\n\n"
                     f"# Usage digest (hx swarm usage, last {a['window_min']} min)\n```json\n{digest}\n```\n")
            # the auditor runs outside the turn slots so a busy swarm can't starve it
            prompt, timeout = self.budgeted("auditor", compose("auditor", "auditor", extra), a["turn_timeout_s"])
            run_turn("auditor", prompt, timeout=timeout, kind="audit")
            mv = [e for e in events(t0) if e["kind"] == "verdict" and e.get("by") != "rules"]
            if mv and SEVERITY.get(mv[-1]["verdict"], 0) > SEVERITY[rv["verdict"]]:
                final = {"verdict": mv[-1]["verdict"], "reason": f"auditor escalated: {mv[-1].get('reason', '')}",
                         "fail": [mv[-1].get("reason", "")] if mv[-1]["verdict"] == "FAIL" else [],
                         "act": [] if mv[-1]["verdict"] == "FAIL" else [mv[-1].get("reason", "")], "health": []}
        if rv["verdict"] != "FAIL":
            self.apply_verdict(final)

    def apply_verdict(self, v: dict) -> None:
        """Counts the verdict (FAIL +1, PASS resets, WARN leaves the streak) and alerts the orchestrator only
        about what it can act on: a FAIL, or WARN findings it can fix. Health-only WARNs (throttling, slow
        turns) stay on STATUS.md."""
        def bump(s: dict) -> None:
            if v["verdict"] == "FAIL":
                s["alert_streak"] += 1
            elif v["verdict"] == "PASS":
                s["alert_streak"] = 0
            s["last_verdict"] = v["verdict"]
        s = update_state(bump)
        log(f"audit {v['verdict']} fail_streak={s['alert_streak']}: {v.get('reason', '')[:200]}")
        limit = self.c["audit"]["fail_streak"]
        if v["verdict"] == "FAIL":
            send_mail("orchestrator", "auditor",
                      f"AUDIT FAIL (consecutive FAILs: {s['alert_streak']}; the orchestrator stops at {limit}).\n"
                      + "\n".join(f"- {x}" for x in v["fail"]) + "\n\n"
                      "Before anything else this turn: run `harness/bin/hx swarm selfcheck`, confirm every delegation goes through "
                      "`hx swarm spawn` / `hx swarm research` (Qwen only), fix what the alert names, and write what you checked and "
                      "changed in your journal under a heading `Audit response`.")
        elif v["act"]:
            send_mail("orchestrator", "auditor",
                      "AUDIT WARN: compliance is clean (no selfcheck needed). Act on these this turn, before new spawns:\n"
                      + "\n".join(f"- {x}" for x in v["act"]))
        if s["alert_streak"] >= limit:
            self.postmortem(v)

    def postmortem(self, v: dict) -> None:
        s = load_state()
        day_ago = now() - timedelta(days=1)
        recent = [p for p in s["postmortems"] if datetime.fromisoformat(p) > day_ago]
        self.orch_paused.set()
        incident = DOCS / "incidents" / f"{stamp()}-generation-{s['generation']}.md"
        _write(incident, f"# Orchestrator stopped: generation {s['generation']}\n\n"
                         f"{s['alert_streak']} failed audits in a row. Last verdict: {v.get('reason', '')}\n\n"
                         f"Recent verdicts:\n" + "\n".join(f"- {e['ts']} {e['verdict']}: {e.get('reason', '')[:300]}"
                                                         for e in [e for e in events() if e['kind'] == 'verdict'][-6:]) + "\n")
        event("incident", generation=s["generation"], file=str(incident.relative_to(ROOT)))
        log(f"orchestrator generation {s['generation']} stopped after {s['alert_streak']} failed audits")
        _bd_human(f"Swarm orchestrator stopped (generation {s['generation']})",
                  f"See {incident.relative_to(ROOT).as_posix()}. A Qwen postmortem is adjusting role prompts and restarting.")
        if len(recent) >= self.c["audit"]["max_postmortems_per_day"]:
            _append(incident, "\nToo many postmortems in 24 h: the swarm stopped and waits for the user.\n")
            commit_docs("swarm: incident, stopping for the user")
            self.stop.set()
            return
        extra = (f"# Incident\nRead `{incident.relative_to(ROOT).as_posix()}`. Logs: `harness/data/swarm/logs/` "
                 f"(orchestrator, designer and researcher turns; `.prompt.md` is what each was given). Events: "
                 f"`harness/data/swarm/events.jsonl`. Audits: `docs/swarm/audits/`.\n")
        prompt, timeout = self.budgeted("postmortem", compose("postmortem", "postmortem", extra), self.c["audit"]["turn_timeout_s"] * 2)
        run_turn("postmortem", prompt, timeout=timeout, kind="postmortem")
        update_state(lambda s: (s.__setitem__("generation", s["generation"] + 1), s.__setitem__("alert_streak", 0),
                                s["postmortems"].append(now().isoformat())))
        commit_docs(f"swarm: postmortem for generation {s['generation']}, prompts adjusted")
        self.orch_paused.clear()

    def retro_loop(self) -> None:
        self.wait(self.c["retro"]["every_s"])
        while self.alive():
            self.hold_support()
            if not self.alive():
                break
            self.turn("retro", compose("retro", "retro"), pool="support", timeout=self.c["retro"]["turn_timeout_s"], group="retro")
            commit_docs("swarm: retro")
            self.wait(self.c["retro"]["every_s"])

    def housekeeping_loop(self) -> None:
        while self.alive():
            try:
                write_status()
                r = commit_docs("swarm: docs and status")
                if r.startswith("commit failed"):
                    log(r)
            except Exception as e:  # noqa: BLE001
                log(f"housekeeping: {e!r}")
            self.wait(self.c["run"]["commit_every_s"])

    def run(self) -> None:
        if sys.platform == "win32":  # keep the PC awake while the swarm runs (cleared when this process exits)
            import ctypes
            ctypes.windll.kernel32.SetThreadExecutionState(0x80000000 | 0x00000001)  # ES_CONTINUOUS | ES_SYSTEM_REQUIRED
        _write(STATE / "supervisor.pid", str(os.getpid()))
        (STATE / "STOP").unlink(missing_ok=True)
        for j in jobs():  # turns killed with a previous supervisor: run them again (the worktree keeps their commits)
            if j["status"] == "running":
                j["status"] = "queued"
                save_job(j)
        d = STATE / "research"
        for p in d.glob("*.json") if d.exists() else []:
            r = json.loads(p.read_text(encoding="utf-8"))
            if r["status"] == "running":
                r["status"] = "queued"
                _write(p, json.dumps(r))
        log(f"supervisor start pid={os.getpid()} end_at={self.end.isoformat()}")
        event("supervisor_start", pid=os.getpid())
        threads = [threading.Thread(target=self._guard, args=(self.orchestrator_loop,), name="orchestrator"),
                   threading.Thread(target=self._guard, args=(self.audit_loop,), name="audit"),
                   threading.Thread(target=self._guard, args=(self.research_loop,), name="research"),
                   threading.Thread(target=self._guard, args=(self.retro_loop,), name="retro"),
                   threading.Thread(target=self._guard, args=(self.housekeeping_loop,), name="housekeeping"),
                   threading.Thread(target=self._guard, args=(self.pipeline_loop,), name="pipeline"),
                   threading.Thread(target=self._guard, args=(lambda: self.periodic_loop("designers"),), name="designers"),
                   threading.Thread(target=self._guard, args=(lambda: self.periodic_loop("researchers"),), name="researchers")]
        for t in threads:
            t.daemon = True
            t.start()
        self.start_workers()
        try:
            while self.alive():
                time.sleep(5)
                try:
                    self.maybe_reload()
                except Exception as e:  # noqa: BLE001 - a reload problem must never stop the swarm
                    log(f"config reload: {e!r}")
        finally:
            self.stop.set()
            self.shutdown(threads + self.worker_threads)
        write_status()
        commit_docs("swarm: final status")
        event("supervisor_stop")
        (STATE / "supervisor.pid").unlink(missing_ok=True)

    def shutdown(self, threads: list[threading.Thread], grace_s: float = 120) -> list[int]:
        """Ends the running turns instead of orphaning them (sw-0zi.11), then gives the loops time to wrap
        up (a stopped worker saves its WIP and goes back in the queue). Returns the pids it killed."""
        killed = stop_turns()
        log(f"supervisor stopping: ended {len(killed)} running turn(s)")
        deadline = time.time() + grace_s
        for t in threads:
            t.join(timeout=max(0.1, deadline - time.time()))
        late = stop_turns()  # a turn that started while we were stopping
        return killed + [p for p in late if p not in killed]

    def _guard(self, fn) -> None:
        """A crashing loop restarts after a pause instead of silently dying."""
        while self.alive():
            try:
                fn()
                return
            except Exception as e:  # noqa: BLE001
                log(f"{threading.current_thread().name} crashed: {e!r}; restarting in 120 s")
                event("loop_crash", loop=threading.current_thread().name, error=repr(e)[:300])
                self.wait(120)


def _bd_human(title: str, body: str) -> None:
    r = subprocess.run(["bd", "create", f"--title={title}", f"--description={body}", "--type=bug", "--priority=1",
                        "--labels=swarm,swarm-incident", "--silent"], cwd=ROOT, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", stdin=subprocess.DEVNULL, timeout=60)
    bid = r.stdout.strip().split()[-1] if r.stdout.strip() else ""
    if bid:
        subprocess.run(["bd", "human", bid], cwd=ROOT, capture_output=True, stdin=subprocess.DEVNULL, timeout=60)


def write_status() -> None:
    s = load_state()
    js = jobs()
    ev = events(now() - timedelta(hours=24))
    verdicts = [e for e in events() if e["kind"] == "verdict"][-5:]
    by = lambda st: [j["bead"] for j in js if j["status"] == st]  # noqa: E731
    gw = _gateway_rows(now() - timedelta(hours=1))
    rl = sum("RateLimit" in (r.get("error") or "") for r in gw)
    lines = [
        "# Swarm status", "",
        f"Updated {clock.stamp()}. Generation {s['generation']}, audit alert streak {s['alert_streak']}. "
        f"Supervisor {'running' if supervisor_pid() else 'stopped'}.", "",
        "| | |", "|---|---|",
        f"| Turns per role | {', '.join(f'{k}: {v}' for k, v in sorted(s['turns'].items()) if not k.startswith(('worker-', 'research-'))) or '-'} |",
        f"| Worker turns / research turns (24 h) | {sum(e['kind'] == 'worker' for e in ev)} / {sum(e['kind'] == 'research' for e in ev)} |",
        f"| Workers queued / running / awaiting review | {', '.join(by('queued')) or '-'} / {', '.join(by('running')) or '-'} / {', '.join(by('done') + by('partial')) or '-'} |",
        f"| Merged / rejected (all time) | {len(by('merged'))} / {len(by('rejected'))} |",
        f"| Gateway calls last hour (rate-limited) | {len(gw)} ({rl}) |",
        f"| Incidents | {len(s['postmortems'])} postmortem(s) |",
        f"| Latest audit | {_audit_line(verdicts[-1]) if verdicts else '-'} |", "",
        "## Recently merged", *[f"- {j['bead']} ({j.get('merged', '')[:16]})" for j in sorted(js, key=lambda j: j.get('merged', ''))[-8:] if j['status'] == 'merged'],
        "", STATUS_DETAILS, "",
        "## Last audits (newest first)", "",
    ]
    for e in reversed(verdicts):  # the full reason: the auditor's report holds the table and recommendations
        lines += [f"### {_audit_line(e)}", "", e.get("reason", "").strip() or "(no reason given)", ""]
    _write(DOCS / "STATUS.md", "\n".join(lines) + "\n")


# compose() gives agents only the status above this marker, so long audit text never crowds out the summary
STATUS_DETAILS = "<!-- details: agents see only the summary above -->"


def _audit_line(e: dict) -> str:
    t = datetime.fromisoformat(e["ts"])
    if e.get("by") == "rules":  # the deterministic audit (sw-0zi.4) writes no report
        return f"{clock.stamp(t, '%m-%d %H:%M')} **{e['verdict']}** (rules)"
    f = _audit_report(t)
    link = f" ([report](audits/{f.name}))" if f else ""
    return f"{clock.stamp(t, '%m-%d %H:%M')} **{e['verdict']}** (auditor){link}"


def _audit_report(t: datetime) -> Path | None:
    """The auditor names its report after the end of the window it read: a few minutes before the verdict."""
    best = None
    for f in (DOCS / "audits").glob("*.md") if (DOCS / "audits").exists() else []:
        try:
            ft = datetime.strptime(f.stem, "%Y%m%d-%H%M").replace(tzinfo=timezone.utc)
        except ValueError:
            continue
        if timedelta(minutes=-10) <= t - ft <= timedelta(minutes=45) and (best is None or ft > best[0]):
            best = (ft, f)
    return best[1] if best else None


def start() -> int:
    pid = supervisor_pid()
    if pid:
        return pid
    env = dict(os.environ, PYTHONPATH=str(ROOT / "harness" / "src"), PYTHONUTF8="1")
    proc = background.spawn([sys.executable, "-m", "hx.cli", "swarm", "run"], ROOT / "harness", env, STATE / "supervisor.out")
    _write(STATE / "supervisor.pid", str(proc.pid))
    return proc.pid


def children(pid: int) -> list[int]:
    """Live processes whose parent is `pid` (the supervisor's turns, also after it exited)."""
    try:
        if sys.platform == "win32":
            r = subprocess.run(["powershell", "-NoProfile", "-Command",
                                f"Get-CimInstance Win32_Process -Filter 'ParentProcessId={int(pid)}' | "
                                "ForEach-Object { $_.ProcessId }"], capture_output=True, text=True, timeout=60)
        else:
            r = subprocess.run(["ps", "-o", "pid=", "--ppid", str(int(pid))], capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return []
    return [int(x) for x in r.stdout.split() if x.strip().isdigit()]


def stop(wait_s: float = 180) -> dict:
    """Writes STOP, waits for the supervisor to end its turns and exit, then kills any process it left
    behind (sw-0zi.11: on 2026-11-22 three turns ran on for 30 min after a stop)."""
    pid = supervisor_pid()
    _write(STATE / "STOP", now().isoformat())
    out = {"was_running": pid is not None, "exited": True, "orphans_killed": []}
    if pid is None:
        return out
    deadline = time.time() + wait_s
    while supervisor_pid() == pid and time.time() < deadline:
        time.sleep(2)
    out["exited"] = supervisor_pid() != pid
    if out["exited"]:
        for c in children(pid):
            background.kill_tree(c)
            out["orphans_killed"].append(c)
        if out["orphans_killed"]:
            log(f"hx swarm stop: killed {len(out['orphans_killed'])} process(es) left by supervisor {pid}")
    return out
