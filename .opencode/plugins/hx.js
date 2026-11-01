// hx hooks for OpenCode 2.x (harness/DESIGN.md §6, §7). Plugin format: default { id, setup(api) }.
//
// 1. Worker jobs (sw-lbm.16): queue an hx worker job after each OpenCode turn, mirroring the Claude Code
//    SessionEnd hook. api.event.subscribe() is an async iterable; its `types` filter delivered nothing
//    in 2.2.0, so events are filtered here. A one-shot `opencode run` exits before the enqueue finishes;
//    the long-lived OpenCode service (desktop app / TUI) runs it fully.
// 2. rtk A/B (sw-lbm.24): api.tool.hook("execute.before") may rewrite a tool's input. Shell commands go
//    through harness/bin/rtk-hook, the same script Claude Code's PreToolUse hook runs, so both clients
//    share one arm hash and one arms log (data/raw/rtk/arms.jsonl).
import { spawn, spawnSync } from "node:child_process"
import { existsSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

// The repo is two levels up from this file; the OpenCode service's cwd is elsewhere.
const REPO = join(dirname(fileURLToPath(import.meta.url)), "..", "..")
const DONE = new Set(["session.execution.succeeded", "session.execution.failed"])
const GIT_BASH = ["C:/Program Files/Git/bin/bash.exe"].find(existsSync) ?? "bash"  // not WSL's bash.exe

const hx = (args) => new Promise((resolve) => {
  try {
    const c = spawn("uv", ["run", "--project", join(REPO, "harness"), "--quiet", "hx", ...args],
                    { stdio: "ignore", windowsHide: true })
    c.on("error", resolve)
    c.on("exit", resolve)
  } catch { resolve() }
})

// rtk rewrite for this session's arm, or null to leave the command alone.
const rtkRewrite = (sessionID, command) => {
  try {
    const p = spawnSync(GIT_BASH, [join(REPO, "harness", "bin", "rtk-hook")], {
      input: JSON.stringify({ session_id: sessionID, tool_name: "Bash", tool_input: { command } }),
      encoding: "utf8", timeout: 10000, windowsHide: true,
    })
    const out = (p.stdout || "").trim()
    return out ? JSON.parse(out)?.hookSpecificOutput?.updatedInput?.command ?? null : null
  } catch { return null }
}

export default {
  id: "hx-worker",
  setup(api) {
    api.tool.hook("execute.before", (ev) => {
      const command = ev?.input?.command
      if (ev?.tool !== "shell" || typeof command !== "string" || !ev.sessionID) return ev
      const rewritten = rtkRewrite(ev.sessionID, command)
      if (rewritten && rewritten !== command) ev.input = { ...ev.input, command: rewritten }
      return ev
    })

    const events = api.event.subscribe({})
    ;(async () => {
      for await (const e of events) {
        if (!DONE.has(e.type)) continue
        const sid = (e.properties ?? e.data)?.sessionID ?? null
        await hx(["worker", "enqueue", "session_end", "--client", "opencode",
                  "--payload", JSON.stringify({ session_id: sid, event: e.type })])
        await hx(["worker", "start"])
      }
    })().catch(() => {})
  },
}
