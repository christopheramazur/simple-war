"""hx autopilot: headless Claude Code works the `bd ready` backlog, one bead at a time, inside the plan's limits.

Each bead runs as one `claude -p` session (auto permission mode) in its own worktree on branch
`autopilot/<bead>`. When Claude reports the bead done, the autopilot merges it through the swarm's merge gate
(main merged in, tests run on the result, then main fast-forwards and is pushed), and closes the bead. Partial work
stays on the branch for the next attempt; blocked beads are labelled for a person.

Limits: Claude Pro has a 5-hour and a weekly window, shared with the user's own sessions. Readings come from the
status line of interactive sessions (hx.quota) and from the rate-limit events every headless turn streams. A bead
starts only while the 5-hour window is under `five_hour_start_pct` and the weekly window is under a pace line that
spreads `weekly_max_pct` over the week; a running bead is ended (its work kept) when the 5-hour window passes
`five_hour_stop_pct`. Config: harness/config/autopilot.toml, re-read before every bead.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import tomllib
from datetime import datetime, timezone
from pathlib import Path

from hx import background, quota, swarm
from hx.swarm import ROOT, file_lock, git

CFG = ROOT / "harness" / "config" / "autopilot.toml"
STATE = ROOT / "harness" / "data" / "autopilot"
WEEK = 7 * 86400
RESULT = re.compile(r"^\s*\**RESULT:?\**:?\s*(done|partial|blocked)\b[\s\-—–:]*(.*)$", re.I | re.M)
STOPPED, LIMITED, TIMED_OUT = "stopped", "limit", "timeout"


def cfg() -> dict:
    return tomllib.loads(CFG.read_text(encoding="utf-8"))


def now() -> datetime:
    return datetime.now(timezone.utc)


def _append(p: Path, text: str) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    with p.open("a", encoding="utf-8", newline="") as f:
        f.write(text)


def log(msg: str) -> None:
    _append(STATE / "autopilot.log", f"{now():%Y-%m-%d %H:%M:%S}Z {msg}\n")


def event(kind: str, **kw) -> None:
    _append(STATE / "events.jsonl", json.dumps({"ts": now().isoformat(timespec="seconds"), "kind": kind, **kw}) + "\n")


def events(n: int = 50) -> list[dict]:
    f = STATE / "events.jsonl"
    if not f.exists():
        return []
    out = []
    for line in f.read_text(encoding="utf-8").splitlines()[-n:]:
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return out


# ---------------------------------------------------------------- plan limits

def readings() -> dict[str, quota.Snapshot]:
    """The newest reading of each window, from any source (status line, headless turns, probes)."""
    latest: dict[str, quota.Snapshot] = {}
    for s in quota.read_tail(quota.log_path()):
        if s.window in quota.WINDOWS and (s.window not in latest or s.ts >= latest[s.window].ts):
            latest[s.window] = s
    return latest


def weekly_cap(lim: dict, resets_at: float, t: float) -> float:
    """The most of the weekly window the autopilot may have used by time t: weekly_max spread over the week."""
    gone = min(1.0, max(0.0, 1 - (resets_at - t) / WEEK))
    return min(float(lim["weekly_max_pct"]), lim["weekly_max_pct"] * gone + lim["weekly_slack_pct"])


def weekly_unblock(lim: dict, pct: float, resets_at: float) -> float:
    """When the pace line rises above `pct` (the window's reset if pct is already at the weekly maximum)."""
    if pct >= lim["weekly_max_pct"]:
        return resets_at
    return resets_at - WEEK * (1 - (pct - lim["weekly_slack_pct"]) / lim["weekly_max_pct"])


def gate(c: dict, latest: dict[str, quota.Snapshot], t: float) -> tuple[str, str, float]:
    """("go" | "wait" | "probe", why, wait until). "probe": no reading recent enough to decide on."""
    lim = c["limits"]
    if any(w not in latest or t - latest[w].ts > lim["reading_max_age_s"] for w in quota.WINDOWS):
        return "probe", "no recent reading of the plan limits", t
    five, week = latest["five_hour"], latest["seven_day"]
    five_pct = 0.0 if t >= five.resets_at else five.used_pct  # a window that reset since the reading is empty
    week_pct = 0.0 if t >= week.resets_at else week.used_pct
    if five_pct >= lim["five_hour_start_pct"]:
        return "wait", f"5-hour window at {five_pct:.0f}% (starts below {lim['five_hour_start_pct']}%)", five.resets_at
    cap = weekly_cap(lim, week.resets_at, t)
    if week_pct >= cap:
        return ("wait", f"weekly window at {week_pct:.0f}%, pace allows {cap:.0f}% by now",
                weekly_unblock(lim, week_pct, week.resets_at))
    return "go", f"5-hour {five_pct:.0f}%, weekly {week_pct:.0f}% (pace cap {cap:.0f}%)", t


def snapshots_from(o: dict, t: float) -> list[quota.Snapshot]:
    """Readings in a stream-json `rate_limit_event` (utilization 0..1 per window)."""
    out = []
    for w, d in ((o.get("rate_limit_info") or {}).get("unifiedWindows") or {}).items():
        if w in quota.WINDOWS and d.get("utilization") is not None and d.get("resetsAt"):
            out.append(quota.Snapshot(ts=t, window=w, used_pct=round(float(d["utilization"]) * 100, 1),
                                      resets_at=float(d["resetsAt"]), session_id="autopilot"))
    return out


def limit_hit(o: dict) -> bool:
    """The API refused a call: a window is spent."""
    info = o.get("rate_limit_info") or {}
    return info.get("status") == "rejected" or any(
        (d or {}).get("status") == "rejected" for d in (info.get("unifiedWindows") or {}).values())


def record(snaps: list[quota.Snapshot]) -> None:
    if snaps:
        quota.record(snaps, quota.read_tail(quota.log_path()))


def claude_exe() -> str:
    exe = shutil.which("claude")
    if exe:
        return exe
    for p in (Path.home() / ".local" / "bin" / "claude.exe", Path.home() / ".local" / "bin" / "claude"):
        if p.exists():
            return str(p)
    raise FileNotFoundError("claude CLI not found on PATH")


def _env() -> dict:
    env = dict(os.environ, HX_AUTOPILOT="1", PYTHONUTF8="1")
    for k in ("HX_REPO_ROOT", "HX_SWARM", "HX_SWARM_ROLE", "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT"):
        env.pop(k, None)
    return env


def _kw() -> dict:
    return {"creationflags": subprocess.CREATE_NO_WINDOW} if sys.platform == "win32" else {}


def probe() -> list[quota.Snapshot]:
    """One-word haiku call, outside the repo (no project hooks), to read both windows."""
    try:
        r = subprocess.run([claude_exe(), "-p", "--model", "haiku", "--max-turns", "1", "--output-format",
                            "stream-json", "--verbose"], input="Reply with the single word ok.", cwd=tempfile.gettempdir(),
                           capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=180, env=_env(),
                           **_kw())
    except (OSError, subprocess.SubprocessError) as e:
        log(f"probe failed: {e!r}")
        return []
    snaps = []
    for line in r.stdout.splitlines():
        try:
            o = json.loads(line)
        except json.JSONDecodeError:
            continue
        if o.get("type") == "rate_limit_event":
            snaps += snapshots_from(o, time.time())
    record(snaps)
    return snaps


# ---------------------------------------------------------------- jobs

def job_path(bead: str) -> Path:
    return STATE / "jobs" / f"{bead}.json"


def load_job(bead: str) -> dict | None:
    p = job_path(bead)
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else None


def save_job(j: dict) -> None:
    p = job_path(j["bead"])
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(j, indent=1), encoding="utf-8", newline="")


def jobs() -> list[dict]:
    d = STATE / "jobs"
    return [json.loads(p.read_text(encoding="utf-8")) for p in sorted(d.glob("*.json"))] if d.exists() else []


def pick(c: dict, skip: set[str]) -> dict | None:
    """The next bead: the swarm's rules (priority, bugs first, no epics, parents or design interviews), the
    autopilot's own exclusions, and nothing whose named paths overlap a swarm worker's bead."""
    b = c["beads"]
    tried = {j["bead"] for j in jobs() if j.get("attempts", 0) >= b["max_attempts"]}
    busy = [j.get("bead_text", "") for j in swarm.jobs() if j["status"] in ("queued", "running", "done", "partial")]
    rules = {"workers": {"refill_exclude_labels": b["exclude_labels"], "refill_exclude_parents": b["exclude_parents"]}}
    return swarm.pick_ready(swarm._bd_json("ready"), swarm._bd_json("list", "--status=open,in_progress,blocked", "--limit", "0"),
                            busy, rules, skip | tried)


# ---------------------------------------------------------------- one bead

def prompt_for(bead: str, show: str, branch: str, wt: Path, j: dict, c: dict) -> str:
    earlier = ""
    if j.get("attempts"):
        earlier = (f"\n- This is attempt {j['attempts'] + 1}. The branch keeps the earlier attempts' commits "
                   f"(`git log main..HEAD`). Last outcome: {j.get('outcome', '?')}. {j.get('detail', '')}".rstrip())
    return f"""You are the hx autopilot: a headless Claude Code run with nobody watching. Nobody can answer a question,
so never ask one. Decide the way AGENTS.md §6 says, and record the decision in the bead notes.

# Your one task: {bead}
{show.strip()}

# Where you are
- Worktree {wt} on branch {branch}, cut from main. The bead is already claimed for you.{earlier}

# Rules for this run (they override AGENTS.md §2 and §6 where they differ)
- Work only on {bead}, only in this worktree. Do not claim, close or start any other bead, and do not touch the main
  checkout ({ROOT}).
- Commit on this branch with {bead} in every message. Never push, merge, rebase or switch branches: after you finish,
  the autopilot merges main into the branch, runs the tests, and fast-forwards main itself.
- Run the tests that cover your change before you finish: `harness/bin/hx godot check` then `harness/bin/hx godot test`
  for game code, `uv run --project harness pytest -q` for harness code.
- Never run `bd close`. Record decisions and anything left over with `bd update {bead} --append-notes "..."` (never
  --notes, which replaces the notes). File a new bead (`bd create`) for out-of-scope work instead of widening this one.
- If the bead needs the user (a design decision the GDD and harness/DESIGN.md don't settle, an account, a login),
  append a note saying exactly what is needed and stop.
- You have about {c['claude']['max_turns']} turns. Commit each working step, so a run that is cut off keeps its work.

# The last line of your final reply must be exactly one of
RESULT: done - <one sentence: what changed and which tests passed>
RESULT: partial - <one sentence: what is left>
RESULT: blocked - <one sentence: what a person must do>
"""


def claude_cmd(cl: dict) -> list[str]:
    if cl["permission_mode"] == "bypassPermissions":
        raise ValueError("autopilot never runs with bypassPermissions; use auto")
    return [claude_exe(), "-p", "--model", cl["model"], "--permission-mode", cl["permission_mode"],
            "--max-turns", str(cl["max_turns"]), "--output-format", "stream-json", "--verbose"]


def run_claude(c: dict, prompt: str, wt: Path, logf: Path, stop_flag) -> dict:
    """One headless session. Returns {"end": "exit"|stopped|limit|timeout, "rc", "result", "summary", "turns",
    "cost_usd"}. Records every rate-limit reading; ends the session when the 5-hour window passes the stop line."""
    cl, lim = c["claude"], c["limits"]
    cmd = claude_cmd(cl)
    logf.parent.mkdir(parents=True, exist_ok=True)
    logf.with_suffix(".prompt.md").write_text(prompt, encoding="utf-8", newline="")
    out: dict = {"end": "exit", "rc": None, "result": None, "summary": "", "turns": None, "cost_usd": None}
    over = threading.Event()
    p = subprocess.Popen(cmd, cwd=wt, env=_env(), stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace", **_kw())

    def read() -> None:
        with logf.open("w", encoding="utf-8", newline="") as f:
            for line in p.stdout:
                f.write(line)
                f.flush()
                try:
                    o = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if o.get("type") == "rate_limit_event":
                    snaps = snapshots_from(o, time.time())
                    record(snaps)
                    five = next((s for s in snaps if s.window == "five_hour"), None)
                    if limit_hit(o) or (five and five.used_pct >= lim["five_hour_stop_pct"]):
                        over.set()
                elif o.get("type") == "result":
                    text = str(o.get("result") or "")
                    m = None
                    for m in RESULT.finditer(text):
                        pass
                    out.update(result=m.group(1).lower() if m else None, summary=(m.group(2).strip() if m else text[-300:]),
                               turns=o.get("num_turns"), cost_usd=o.get("total_cost_usd"))
    reader = threading.Thread(target=read, daemon=True)
    reader.start()
    try:
        p.stdin.write(prompt)
        p.stdin.close()
    except OSError:
        pass
    deadline = time.time() + cl["timeout_s"]
    while p.poll() is None:
        end = STOPPED if stop_flag() else LIMITED if over.is_set() else TIMED_OUT if time.time() > deadline else None
        if end:
            out["end"] = end
            background.kill_tree(p.pid)
            break
        time.sleep(2)
    try:
        out["rc"] = p.wait(60)
    except subprocess.TimeoutExpired:
        out["rc"] = -9
    reader.join(30)
    return out


def save_wip(wt: Path, bead: str, why: str) -> bool:
    if not wt.exists() or not git("status", "--porcelain", cwd=wt).stdout.strip():
        return False
    git("add", "-A", cwd=wt)
    return not git("commit", "-q", "--no-verify", "-m", f"WIP({bead}): {why}", "-m",
                   "Saved by hx autopilot; the next attempt continues from here.", cwd=wt).returncode


def prepare_worktree(bead: str) -> tuple[Path, str, bool]:
    wt, branch = swarm.WT_ROOT / f"ap-{bead}", f"autopilot/{bead}"
    with file_lock("git"):
        if git("rev-parse", "--verify", "-q", branch).returncode:
            if wt.exists():
                git("worktree", "remove", "--force", str(wt))
            r = git("worktree", "add", "-q", "-b", branch, str(wt), "main")
            continued = False
        else:
            r = subprocess.CompletedProcess([], 0, "", "")
            if not wt.exists():
                git("worktree", "prune")
                r = git("worktree", "add", "-q", str(wt), branch)
            continued = True
        if r.returncode:
            raise RuntimeError("worktree add failed: " + r.stderr[-300:])
    swarm.fill_gitlinks(wt)
    if continued:
        save_wip(wt, bead, "uncommitted work from the previous attempt")
    return wt, branch, continued


def _note(bead: str, text: str) -> None:
    swarm._bd("update", bead, f"--append-notes=autopilot {now():%Y-%m-%d %H:%M}Z: {text}")


def run_bead(c: dict, b: dict, stop_flag=lambda: False) -> dict:
    """Claim, run, then merge, return or label. Returns the job record."""
    bead = b["id"]
    j = load_job(bead) or {"bead": bead, "attempts": 0}
    if swarm._bd("update", bead, "--claim").returncode:
        event("claim_failed", bead=bead)
        return {**j, "outcome": "claim_failed"}
    show = swarm._bd("show", bead).stdout[-6000:]
    wt, branch = Path(), ""
    try:
        wt, branch, continued = prepare_worktree(bead)
    except RuntimeError as e:
        swarm._bd("unclaim", bead)
        event("worktree_failed", bead=bead, error=str(e)[:300])
        return {**j, "outcome": "worktree_failed", "detail": str(e)[:300]}
    stamp = f"{now():%Y%m%d-%H%M%S}"
    j.update(branch=branch, worktree=str(wt), bead_text=show, started=now().isoformat(timespec="seconds"),
             status="running", title=b.get("title", ""))
    save_job(j)
    _state({"current": bead, "since": j["started"]})
    event("start", bead=bead, attempt=j["attempts"] + 1, continued=continued)
    t0 = time.time()
    res = run_claude(c, prompt_for(bead, show, branch, wt, j, c), wt, STATE / "logs" / bead / f"{stamp}.jsonl", stop_flag)
    save_wip(wt, bead, f"autopilot session ended ({res['end']}, rc={res['rc']})")
    commits = int(git("rev-list", "--count", f"main..{branch}").stdout.strip() or 0)
    counts = res["end"] not in (STOPPED, LIMITED)  # not the bead's fault: does not use up an attempt
    j.update(attempts=j["attempts"] + (1 if counts else 0), minutes=round((time.time() - t0) / 60),
             turns=res["turns"], cost_usd=res["cost_usd"], commits=commits, end=res["end"], status="idle")
    outcome = res["result"] or (res["end"] if res["end"] != "exit" else "no_result")
    detail = res["summary"]
    # Partial or blocked work is merged too when it passes the gate: it is usually finished except for a piece
    # that waits on another bead, and left on its branch it was lost (19 beads by 2026-11-23). The bead stays open.
    merged = False
    if res["result"] in ("done", "partial", "blocked") and res["end"] == "exit" and commits:
        try:
            names, push_err = swarm.merge_branch(branch, wt, c["merge"]["test_timeout_s"], swarm.PROTECTED)
            merged = True
            if push_err:
                detail += f" (push failed: {push_err})"
        except ValueError as e:
            outcome, detail = "merge_failed", str(e)[:1200]
    elif res["result"] == "done" and not commits:
        outcome, detail = "no_commits", "reported done but committed nothing"
    if merged and res["result"] == "done":
        swarm._bd("close", bead, f"--reason=merged to main by hx autopilot ({', '.join(names) or 'docs only'} green): {detail}"[:900])
        outcome, j["status"] = "merged", "merged"
    elif merged:
        # what is done is on main; what is left needs a look (often a follow-up bead the session filed)
        swarm._bd("unclaim", bead)
        outcome = f"merged_{res['result']}"
        swarm._bd("update", bead, "--add-label=" + ("autopilot-blocked" if res["result"] == "blocked" else "autopilot-partial"))
    else:
        swarm._bd("unclaim", bead)
        if outcome == "blocked":
            swarm._bd("update", bead, "--add-label=autopilot-blocked")
        elif j["attempts"] >= c["beads"]["max_attempts"]:
            swarm._bd("update", bead, "--add-label=autopilot-failed")
            detail += f" (attempt {j['attempts']} of {c['beads']['max_attempts']}: labelled autopilot-failed)"
    j.update(outcome=outcome, detail=detail[:1200], finished=now().isoformat(timespec="seconds"))
    save_job(j)
    _note(bead, f"{outcome} after {j['minutes']} min, {j['turns'] or '?'} turns, {commits} commit(s) on {branch}. {detail}"[:1500])
    event("finish", bead=bead, outcome=outcome, minutes=j["minutes"], turns=j["turns"], commits=commits)
    _state({"current": None, "since": None})
    return j


# ---------------------------------------------------------------- the loop

def _state(update: dict) -> None:
    p = STATE / "state.json"
    s = json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}
    s.update(update)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(s, indent=1), encoding="utf-8", newline="")


def stop_requested() -> bool:
    return (STATE / "STOP").exists()


def _sleep_until(t: float) -> None:
    while time.time() < t and not stop_requested():
        time.sleep(min(5.0, max(0.1, t - time.time())))


def run_loop(once: bool = False, bead: str | None = None) -> list[dict]:
    """Work beads until stopped. `once`: one bead (or none) and return. `bead`: that bead, once."""
    STATE.mkdir(parents=True, exist_ok=True)
    done: list[dict] = []
    skip: set[str] = set()
    last_wait = ""
    log(f"autopilot started (pid {os.getpid()})")
    while not stop_requested():
        c = cfg()
        decision, why, until = gate(c, readings(), time.time())
        if decision == "probe":
            probe()
            decision, why, until = gate(c, readings(), time.time())
            if decision == "probe":
                log(f"could not read the plan limits: {why}; trying again in 10 min")
                if once:
                    break
                _sleep_until(time.time() + 600)
                continue
        if decision == "wait":
            if why != last_wait:
                event("wait", why=why, until=datetime.fromtimestamp(until, timezone.utc).isoformat(timespec="minutes"))
                log(f"waiting: {why}")
                last_wait = why
            if once:
                break
            _sleep_until(min(until, time.time() + 1800))  # re-check: the user's own use moves the readings too
            continue
        last_wait = ""
        b = {"id": bead, "title": ""} if bead else pick(c, skip)
        if not b:
            if once:
                break
            _sleep_until(time.time() + c["beads"]["idle_s"])
            continue
        j = run_bead(c, b, stop_requested)
        done.append(j)
        if j.get("outcome") in ("claim_failed", "worktree_failed"):
            skip.add(b["id"])
        if once or bead:
            break
    log("autopilot stopped")
    return done


# ---------------------------------------------------------------- lifecycle

def _alive(pid: int) -> bool:
    if sys.platform == "win32":
        r = subprocess.run(["tasklist", "/FI", f"PID eq {pid}", "/NH"], capture_output=True, text=True)
        return str(pid) in r.stdout
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def pid() -> int | None:
    f = STATE / "autopilot.pid"
    if not f.exists():
        return None
    n = int(f.read_text().strip() or 0)
    return n if n and _alive(n) else None


def start() -> int:
    if (n := pid()):
        return n
    (STATE / "STOP").unlink(missing_ok=True)
    env = dict(os.environ, PYTHONPATH=str(ROOT / "harness" / "src"), PYTHONUTF8="1")
    proc = background.spawn([sys.executable, "-m", "hx.cli", "autopilot", "run"], ROOT / "harness", env,
                            STATE / "autopilot.out")
    STATE.mkdir(parents=True, exist_ok=True)
    (STATE / "autopilot.pid").write_text(str(proc.pid), encoding="utf-8")
    return proc.pid


def stop(wait_s: float = 120) -> dict:
    """Asks the loop to stop: a running session is ended, its work kept as a WIP commit, the bead unclaimed."""
    n = pid()
    STATE.mkdir(parents=True, exist_ok=True)
    (STATE / "STOP").write_text(now().isoformat(), encoding="utf-8")
    deadline = time.time() + wait_s
    while n and pid() == n and time.time() < deadline:
        time.sleep(2)
    return {"was_running": n is not None, "exited": pid() != n if n else True}


def status() -> dict:
    c = cfg()
    latest = readings()
    decision, why, until = gate(c, latest, time.time())
    s_file = STATE / "state.json"
    s = json.loads(s_file.read_text(encoding="utf-8")) if s_file.exists() else {}
    return {"pid": pid(), "current": s.get("current"), "since": s.get("since"), "gate": decision, "why": why,
            "readings": {w: {"pct": r.used_pct, "age_min": round((time.time() - r.ts) / 60),
                             "resets": datetime.fromtimestamp(r.resets_at, timezone.utc).isoformat(timespec="minutes")}
                         for w, r in latest.items()},
            "recent": [{k: j.get(k) for k in ("bead", "outcome", "attempts", "minutes", "turns", "finished")}
                       for j in sorted(jobs(), key=lambda j: j.get("finished") or "", reverse=True)[:8]]}
