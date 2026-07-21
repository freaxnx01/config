---
description: Update my user-level slash commands from config + agent-workflow (pull + relink)
---

Update my personal user-level Claude Code slash commands. They now come from **two**
source repos, both installed into `~/.claude/commands/`:

- **[freaxnx01/config](https://github.com/freaxnx01/config)** (`~/repos/github/freaxnx01/public/config`)
  — the generic commands (session hygiene, handoff/pickup, `wt:*`, meta).
- **[freaxnx01/agent-workflow](https://github.com/freaxnx01/agent-workflow)** (`~/repos/github/freaxnx01/public/agent-workflow`)
  — the issue-workflow operator console (forge routers, `gh:*`, `fj:*`, `capture-idea`).

Steps:

1. Run the idempotent config installer. It pulls the latest `main` for config,
   re-symlinks the generic commands, **then** clones/pulls agent-workflow and
   re-symlinks the console commands via its own link step — so one command refreshes
   both sources:

   ```bash
   bash ~/repos/github/freaxnx01/public/config/setup/01-claude-commands.sh
   ```

2. Report concisely which commands were added, changed, or removed since before the
   pull. Use the installer output plus, for whichever repos fast-forwarded:

   ```bash
   git -C ~/repos/github/freaxnx01/public/config         log --oneline @{1}.. 2>/dev/null
   git -C ~/repos/github/freaxnx01/public/agent-workflow log --oneline @{1}.. 2>/dev/null
   ```

   If nothing changed in either, just say "Already up to date."

Notes:

- This is read-only (pull + relink) — no auth needed.
- Do **not** confuse this with `/sync-ai-instructions`, which refreshes a *project's*
  `.ai/` + `.claude/commands/` + `CLAUDE.md` from the `freaxnx01/ai-instructions`
  repo. This command is only about the user-level commands shared across all projects.
