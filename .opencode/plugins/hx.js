// Queue an hx worker job after each OpenCode turn (harness/DESIGN.md §7, sw-lbm.16); mirrors the
// Claude Code SessionEnd hook in .claude/settings.json.
// OpenCode 2.x plugin format: default { id, setup(api) }; api.event.subscribe() is an async iterable.
// Its `types` filter delivered nothing in 2.2.0, so events are filtered here.
// Runs in the long-lived OpenCode service (desktop app / TUI). A one-shot `opencode run` exits
// before the enqueue finishes; `hx delegate --agent` runs don't need it (delegate logs itself).
import { spawn } from "node:child_process"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

// The repo is two levels up from this file; the OpenCode service's cwd is elsewhere.
const REPO = join(dirname(fileURLToPath(import.meta.url)), "..", "..")
const DONE = new Set(["session.execution.succeeded", "session.execution.failed"])

const hx = (args) => new Promise((resolve) => {
  try {
    const c = spawn("uv", ["run", "--project", join(REPO, "harness"), "--quiet", "hx", ...args],
                    { stdio: "ignore", windowsHide: true })
    c.on("error", resolve)
    c.on("exit", resolve)
  } catch { resolve() }
})

export default {
  id: "hx-worker",
  setup(api) {
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
