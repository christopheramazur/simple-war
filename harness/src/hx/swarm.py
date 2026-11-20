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

from hx import background, paths

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
             "harness/src/hx/commands/delegate.py", "opencode.json", ".mcp.json"}


def now() -> datetime:
    return datetime.now(timezone.utc)


def stamp(t: datetime | None = None) -> str:
    return (t or now()).strftime("%Y%m%dT%H%M%SZ")


def cfg() -> dict:
    return tomllib.loads((SWARM / "swarm.toml").read_text(encoding="utf-8"))


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
        _write(STATE / "mail" / n / f"{stamp()}-{sender}-{os.getpid()}.md", f"From: {sender} ({now():%Y-%m-%d %H:%M}Z)\n\n{body.strip()}\n")
    return names


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


def spawn_worker(bead: str, note: str = "") -> dict:
    if not re.fullmatch(r"[A-Za-z0-9._-]+", bead):
        raise ValueError("bad bead id")
    c = cfg()
    j = load_job(bead)
    if j and j["status"] not in DONE | {"failed"}:
        raise ValueError(f"{bead} already has a {j['status']} worker")
    active = [x for x in jobs() if x["status"] in ("queued", "running", "done")]
    if len(active) >= c["workers"]["max_open"]:
        raise ValueError(f"{len(active)} worker jobs are open (queued/running/done awaiting merge); merge or reject some first")
    show = subprocess.run(["bd", "show", bead], cwd=ROOT, capture_output=True, text=True, encoding="utf-8",
                          errors="replace", stdin=subprocess.DEVNULL, timeout=60)
    if show.returncode:
        raise ValueError(f"bd show {bead} failed: {show.stderr.strip()[-200:]}")
    wt, branch = WT_ROOT / bead, f"swarm/{bead}"
    with file_lock("git"):
        if wt.exists():
            git("worktree", "remove", "--force", str(wt))
        git("branch", "-D", branch)
        r = git("worktree", "add", "-q", "-b", branch, str(wt), "HEAD")
        if r.returncode:
            raise ValueError("worktree add failed: " + r.stderr[-300:])
        base = git("rev-parse", "HEAD").stdout.strip()
    attempts = (j or {}).get("attempts", 0) + 1
    j = {"bead": bead, "status": "queued", "worktree": str(wt), "branch": branch, "base": base,
         "created": now().isoformat(timespec="seconds"), "attempts": attempts, "note": note,
         "bead_text": show.stdout[-6000:], "summary": ""}
    save_job(j)
    event("spawn", bead=bead, attempts=attempts)
    return j


def _checks_for(changed: list[str]) -> list[list[str]]:
    checks = []
    if any(not f.startswith(("harness/", "docs/", ".beads/")) for f in changed):
        checks.append(["bash", "harness/bin/hx", "godot", "test"])
    if any(f.startswith("harness/") for f in changed):
        checks.append(["uv", "run", "--project", "harness", "pytest", "-q", "-x"])
    return checks


def merge_worker(bead: str) -> str:
    """Bring main into the worker branch, run the tests there, then fast-forward main. Main never goes red."""
    j = load_job(bead)
    if not j or j["status"] != "done":
        raise ValueError(f"{bead}: no finished worker to merge (status {j and j['status']})")
    wt = Path(j["worktree"])
    timeout = cfg()["merge"]["test_timeout_s"]
    env = {k: v for k, v in os.environ.items() if k != "HX_REPO_ROOT"}
    commit_docs("swarm: docs before merge")
    for _ in range(3):
        with file_lock("git"):
            if git("rev-list", "--count", f"HEAD..{j['branch']}").stdout.strip() in ("", "0"):
                raise ValueError(f"{j['branch']} has no commits that main lacks; reject it or re-spawn")
            r = git("merge", "--no-edit", "-m", f"Merge main into {j['branch']}", "main", cwd=wt)
            if r.returncode:
                git("merge", "--abort", cwd=wt)
                raise ValueError("main does not merge cleanly into the worker branch; reject and re-spawn the bead on "
                                 "the new main: " + (r.stdout + r.stderr)[-400:])
        changed = git("diff", "--name-only", "main...HEAD", cwd=wt).stdout.split()
        if bad := [f for f in changed if f in PROTECTED]:
            raise ValueError(f"the branch changes protected swarm guardrail files {bad}; reject it (only the user changes these)")
        checks = _checks_for(changed)
        for c in checks:
            t = subprocess.run(c, cwd=wt, capture_output=True, text=True, encoding="utf-8", errors="replace",
                               stdin=subprocess.DEVNULL, timeout=timeout, env=env)
            if t.returncode:
                event("merge_red", bead=bead, check=" ".join(c[-2:]))
                raise ValueError(f"tests failed on the merged branch ({' '.join(c[-2:])}); main is untouched. "
                                 f"Send it back to a worker or reject it. Tail:\n" + (t.stdout + t.stderr)[-1500:])
        with file_lock("git"):
            ff = git("merge", "--ff-only", j["branch"])
            if ff.returncode:
                if git("merge-base", "--is-ancestor", "HEAD", j["branch"]).returncode:
                    continue  # main moved while we tested: merge it in and test again
                raise ValueError("fast-forward of main failed (uncommitted changes in the main checkout?): "
                                 + (ff.stdout + ff.stderr)[-400:])
            p = git("push", "-q", "origin", "HEAD")
            git("worktree", "remove", "--force", j["worktree"])
            git("branch", "-D", j["branch"])
        names = [" ".join(c[-2:]) for c in checks]
        j.update(status="merged", merged=now().isoformat(timespec="seconds"), checks=names)
        save_job(j)
        event("merge", bead=bead, pushed=not p.returncode, checks=names)
        return (f"merged ({', '.join(names) or 'docs only, no tests'} green)"
                + ("" if not p.returncode else "; push failed: " + p.stderr[-200:]))
    raise ValueError("main kept moving during the tests; run the merge again")


def ask(question: str, sender: str) -> None:
    _append(DOCS / "questions.md", f"\n## {now():%Y-%m-%d %H:%M}Z from {sender}\n{question.strip()}\n")
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
           f"- You are: **{role}**. Generation {s['generation']}. Time now: {now():%Y-%m-%d %H:%M} UTC. "
           f"The run ends {c['run']['end_at']}.\n"
           f"- Repo (main checkout): `{ROOT.as_posix()}`. Your journal: `docs/swarm/journals/{role}.md`.\n\n"
           f"## Your inbox (new since your last turn)\n{mail or '(empty)'}\n\n"
           f"## Your journal (last 40 lines)\n{_tail(DOCS / 'journals' / f'{role}.md', 40)}\n\n"
           f"## Swarm status\n{status[-3000:]}\n")
    return f"{common}\n\n{body}\n\n{ctx}\n{extra}".strip() + "\n"


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
        try:
            rc = p.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            background.kill_tree(p.pid)
            rc = -9
    dur = round(time.time() - t0)
    text = logf.read_text(encoding="utf-8", errors="replace")
    rate_limited = text.count("rate limit") + text.count("RateLimit")
    event(kind, role=role, rc=rc, seconds=dur, rate_limited=rate_limited, log=str(logf.relative_to(STATE)))
    update_state(lambda s: s["turns"].__setitem__(role, s["turns"].get(role, 0) + 1))
    return rc, text


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


class Supervisor:
    def __init__(self) -> None:
        self.c = cfg()
        self.stop = threading.Event()
        self.orch_paused = threading.Event()   # set while a postmortem runs
        self.slots = threading.BoundedSemaphore(self.c["run"]["max_concurrent_turns"])
        self.end = datetime.fromisoformat(self.c["run"]["end_at"])

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

    def backoff(self) -> float:
        """Seconds to add between turns when Nous is rate-limiting (share of 429s in the last 10 min)."""
        rows = _gateway_rows(now() - timedelta(minutes=10))
        if len(rows) < 10:
            return 0
        share = sum("RateLimit" in (r.get("error") or "") for r in rows) / len(rows)
        return 0 if share < 0.2 else min(900, 60 + 1200 * share)

    def turn(self, role: str, prompt: str, **kw) -> tuple[int, str]:
        with self.slots:
            if not self.alive():
                return -1, ""
            return run_turn(role, prompt, **kw)

    # -- loops
    def orchestrator_loop(self) -> None:
        fails = 0
        while self.alive():
            if self.orch_paused.is_set():
                self.wait(30)
                continue
            rc, _ = self.turn("orchestrator", compose("orchestrator", "orchestrator"),
                              timeout=self.c["orchestrator"]["turn_timeout_s"])
            fails = fails + 1 if rc else 0
            self.wait(self.c["orchestrator"]["pause_s"] + self.backoff() + min(1800, 60 * 2 ** fails if fails else 0))

    def worker_loop(self, n: int) -> None:
        while self.alive():
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
                                 cwd=Path(j["worktree"]), timeout=self.c["workers"]["timeout_s"], kind="worker")
            ahead = git("rev-list", "--count", f"{j['base']}..{j['branch']}").stdout.strip()
            summary = text[-3500:]
            m = re.search(r"WORKER RESULT.*", text, re.S)
            if m:
                summary = m.group(0)[:3500]
            j.update(status="done" if ahead not in ("", "0") else "failed", finished=now().isoformat(timespec="seconds"),
                     rc=rc, commits=int(ahead or 0), summary=summary)
            save_job(j)
            event("worker_done", bead=j["bead"], status=j["status"], commits=j["commits"], rc=rc)
            send_mail("orchestrator", "supervisor",
                      f"Worker for {j['bead']} finished: status **{j['status']}**, {j['commits']} commit(s), rc={rc}.\n"
                      f"Review with `git -C {j['worktree']} log -p {j['base'][:9]}..HEAD` then `hx swarm merge {j['bead']}` "
                      f"or `hx swarm reject {j['bead']} --reason ...`.\n\nWorker's report:\n{summary[-1500:]}")
            self.wait(5)

    def periodic_loop(self, group: str) -> None:
        sec = self.c[group]
        roles = list(sec["roles"])
        i = 0
        self.wait(sec.get("initial_delay_s", 60))
        while self.alive():
            role = roles[i % len(roles)]
            self.turn(role, compose(role, [sec["base"], role]), timeout=sec["turn_timeout_s"])
            i += 1
            self.wait(max(60, sec["every_s"] / len(roles)) + self.backoff())

    def research_loop(self) -> None:
        while self.alive():
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
            rc, _ = self.turn(f"research-{j['slug'][:30]}", compose("deep-researcher", "deep-researcher", extra, inbox=""),
                              timeout=self.c["research"]["timeout_s"], kind="research")
            j.update(status="done" if out.exists() else "failed", finished=now().isoformat(timespec="seconds"))
            _write(p, json.dumps(j))
            send_mail("researchers", "supervisor", f"Deep research `{j['slug']}` finished: {j['status']}. Report: `{out.relative_to(ROOT).as_posix()}`.")
            event("research_done", slug=j["slug"], status=j["status"])

    def audit_loop(self) -> None:
        a = self.c["audit"]
        self.wait(a["every_s"])
        while self.alive():
            if not self.orch_paused.is_set():
                self.run_audit()
            self.wait(a["every_s"])

    def run_audit(self) -> None:
        t0 = now()
        digest = json.dumps(usage(self.c["audit"]["window_min"]), indent=1)[:20000]
        extra = f"# Usage digest (hx swarm usage, last {self.c['audit']['window_min']} min)\n```json\n{digest}\n```\n"
        # the auditor runs outside the turn slots so a busy swarm can't starve it
        run_turn("auditor", compose("auditor", "auditor", extra), timeout=self.c["audit"]["turn_timeout_s"], kind="audit")
        verdicts = [e for e in events(t0) if e["kind"] == "verdict"]
        v = verdicts[-1] if verdicts else {"verdict": "WARN", "reason": "auditor recorded no verdict"}
        if not verdicts:
            event("verdict", verdict="WARN", reason=v["reason"], by="supervisor")

        def bump(s: dict) -> None:  # FAIL counts, PASS resets, WARN alerts without counting
            if v["verdict"] == "FAIL":
                s["alert_streak"] += 1
            elif v["verdict"] == "PASS":
                s["alert_streak"] = 0
        s = update_state(bump)
        log(f"audit {v['verdict']} fail_streak={s['alert_streak']}: {v.get('reason', '')[:200]}")
        if v["verdict"] in ("WARN", "FAIL"):
            send_mail("orchestrator", "auditor",
                      f"AUDIT {v['verdict']} (consecutive FAILs: {s['alert_streak']}; the orchestrator stops at "
                      f"{self.c['audit']['fail_streak']}).\n{v.get('reason', '')}\n\n"
                      "Before anything else this turn: run `harness/bin/hx swarm selfcheck`, confirm every delegation goes through "
                      "`hx swarm spawn` / `hx swarm research` (Qwen only), fix what the alert names, and write what you checked and "
                      "changed in your journal under a heading `Audit response`.")
        if s["alert_streak"] >= self.c["audit"]["fail_streak"]:
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
        run_turn("postmortem", compose("postmortem", "postmortem", extra), timeout=self.c["audit"]["turn_timeout_s"] * 2, kind="postmortem")
        update_state(lambda s: (s.__setitem__("generation", s["generation"] + 1), s.__setitem__("alert_streak", 0),
                                s["postmortems"].append(now().isoformat())))
        commit_docs(f"swarm: postmortem for generation {s['generation']}, prompts adjusted")
        self.orch_paused.clear()

    def retro_loop(self) -> None:
        r = self.c["retro"]
        self.wait(r["every_s"])
        while self.alive():
            self.turn("retro", compose("retro", "retro"), timeout=r["turn_timeout_s"])
            commit_docs("swarm: retro")
            self.wait(r["every_s"])

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
                   threading.Thread(target=self._guard, args=(lambda: self.periodic_loop("designers"),), name="designers"),
                   threading.Thread(target=self._guard, args=(lambda: self.periodic_loop("researchers"),), name="researchers")]
        threads += [threading.Thread(target=self._guard, args=(lambda n=n: self.worker_loop(n),), name=f"worker{n}")
                    for n in range(self.c["workers"]["max_parallel"])]
        for t in threads:
            t.daemon = True
            t.start()
        while self.alive():
            time.sleep(5)
        log("supervisor stopping")
        for t in threads:
            t.join(timeout=5)
        write_status()
        commit_docs("swarm: final status")
        event("supervisor_stop")
        (STATE / "supervisor.pid").unlink(missing_ok=True)

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
        f"Updated {now():%Y-%m-%d %H:%M} UTC. Generation {s['generation']}, audit alert streak {s['alert_streak']}. "
        f"Supervisor {'running' if supervisor_pid() else 'stopped'}.", "",
        "| | |", "|---|---|",
        f"| Turns per role | {', '.join(f'{k}: {v}' for k, v in sorted(s['turns'].items()) if not k.startswith(('worker-', 'research-'))) or '-'} |",
        f"| Worker turns / research turns (24 h) | {sum(e['kind'] == 'worker' for e in ev)} / {sum(e['kind'] == 'research' for e in ev)} |",
        f"| Workers queued / running / awaiting review | {', '.join(by('queued')) or '-'} / {', '.join(by('running')) or '-'} / {', '.join(by('done')) or '-'} |",
        f"| Merged / rejected (all time) | {len(by('merged'))} / {len(by('rejected'))} |",
        f"| Gateway calls last hour (rate-limited) | {len(gw)} ({rl}) |",
        f"| Incidents | {len(s['postmortems'])} postmortem(s) |", "",
        "## Last audits", *[f"- {e['ts']} **{e['verdict']}** {e.get('reason', '')[:240]}" for e in verdicts], "",
        "## Recently merged", *[f"- {j['bead']} ({j.get('merged', '')[:16]})" for j in sorted(js, key=lambda j: j.get('merged', ''))[-8:] if j['status'] == 'merged'],
    ]
    _write(DOCS / "STATUS.md", "\n".join(lines) + "\n")


def start() -> int:
    pid = supervisor_pid()
    if pid:
        return pid
    env = dict(os.environ, PYTHONPATH=str(ROOT / "harness" / "src"), PYTHONUTF8="1")
    proc = background.spawn([sys.executable, "-m", "hx.cli", "swarm", "run"], ROOT / "harness", env, STATE / "supervisor.out")
    _write(STATE / "supervisor.pid", str(proc.pid))
    return proc.pid


def stop() -> bool:
    _write(STATE / "STOP", now().isoformat())
    return supervisor_pid() is not None
