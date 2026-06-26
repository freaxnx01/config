---
description: Update my user-level slash commands from the config repo (pull + relink)
---

Update my personal user-level Claude Code slash commands from the config repo
**https://github.com/freaxnx01/config** (local clone:
`~/repos/github/freaxnx01/public/config`).

Steps:

1. Run the idempotent installer, which pulls the latest `main` and re-symlinks
   every command into `~/.claude/commands/` (picking up any new files):

   ```bash
   bash ~/repos/github/freaxnx01/public/config/setup/01-claude-commands.sh
   ```

2. Report concisely which commands were added, changed, or removed since before
   the pull — use the installer output plus `git -C ~/repos/github/freaxnx01/public/config log --oneline @{1}..` if a fast-forward happened. If nothing changed, just say "Already up to date."

Notes:

- This is read-only (pull + relink) — no auth needed.
- Do **not** confuse this with `/sync-ai-instructions`, which refreshes a
  *project's* `.ai/` + `.claude/commands/` + `CLAUDE.md` from the
  `freaxnx01/ai-instructions` repo. This command is only about the user-level
  commands shared across all projects.
