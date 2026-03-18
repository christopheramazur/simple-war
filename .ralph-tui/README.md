# Ralph TUI + Beads + Cursor Agent Setup

This project is configured for [Ralph TUI](https://ralph-tui.com/docs) with the [Beads](https://github.com/steveyegge/beads) tracker and the Cursor Agent CLI as the coding agent.

## One-time: Finish Beads init (requires Dolt)

Beads 0.61+ uses [Dolt](https://docs.dolthub.com/introduction/installation) as the backend. If `bd init` has not been run yet:

1. Install Dolt (when no other Windows installer is running):
   ```powershell
   winget install DoltHub.Dolt
   ```
2. Add Beads to your PATH if needed:
   - Beads: `C:\Users\chris\AppData\Local\Programs\bd`
3. In this repo, run:
   ```powershell
   bd init --quiet
   ```

After that, create epics and tasks with `bd create`, then run Ralph with an epic:
`ralph-tui run --tracker beads --epic <epic-id>`.

## Cursor Agent CLI setup

To use the Cursor Agent CLI (instead of the IDE launcher) as the agent for Ralph:

1. Install the Cursor Agent CLI:
   ```powershell
   irm 'https://cursor.com/install?win32=true' | iex
   ```
2. This script installs the agent into:
   - `C:\Users\chris\AppData\Local\cursor-agent`
3. The project config in `.ralph-tui/config.toml` is set to use:
   ```toml
   agent = "cursor"
   command = "agent"
   tracker = "beads"
   maxIterations = 25
   ```
   This tells Ralph TUI to use the built-in `cursor` agent plugin but invoke the `agent` CLI binary (the headless Cursor agent), not the `cursor` IDE launcher.

## Running Ralph TUI

- **With Beads + Cursor Agent:** `ralph-tui run --tracker beads --epic <epic-id> --agent cursor`
- **Iteration limits** are set in `.ralph-tui/config.toml` (e.g. `maxIterations = 10`) to help manage token/plan usage.
- Use `p` to pause, `q` to quit, `+`/`-` to adjust iterations in the TUI.

## PATH reminder

Ensure these are on your PATH when using Ralph/Beads/Cursor from a terminal:

- **Bun:** `%USERPROFILE%\.bun\bin` (for `ralph-tui`)
- **Beads:** `C:\Users\chris\AppData\Local\Programs\bd` (for `bd`)
- **Dolt:** added by winget (e.g. `C:\Program Files\Dolt`)
- **Cursor IDE CLI:** `C:\Users\chris\AppData\Local\Programs\cursor\resources\app\bin` (for `cursor`)
- **Cursor Agent CLI:** `C:\Users\chris\AppData\Local\cursor-agent` (for `agent`)
