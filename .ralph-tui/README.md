# Ralph TUI + Beads Setup

This project is configured for [Ralph TUI](https://ralph-tui.com/docs) with the [Beads](https://github.com/steveyegge/beads) tracker.

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

## Running Ralph TUI

- **With Beads (after init):** `ralph-tui run --tracker beads --epic <epic-id>`
- **Iteration limits** are set in `.ralph-tui/config.toml` (e.g. `maxIterations = 5`) to help manage token/plan usage.
- Use `p` to pause, `q` to quit, `+`/`-` to adjust iterations in the TUI.

## PATH reminder

Ensure these are on your PATH when using Ralph/Beads from a terminal:

- **Bun:** `%USERPROFILE%\.bun\bin` (for `ralph-tui`)
- **Beads:** `C:\Users\chris\AppData\Local\Programs\bd` (for `bd`)
- **Dolt:** added by winget (e.g. `C:\Program Files\Dolt`)
