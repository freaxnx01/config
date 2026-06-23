# Claude Code shared slash commands

User-level [custom slash commands](https://docs.anthropic.com/en/docs/claude-code/slash-commands#custom-slash-commands)
for Claude Code. Each `.md` file becomes a `/<filename>` command; the
`description:` front-matter shows in the `/` autocomplete menu.

| Command | What it does |
|---------|--------------|
| [`/loose-ends`](loose-ends.md) | Lists anything started but not finished in the session — uncommitted edits, unrun/failing tests, queued commands, open follow-ups. |
| [`/clear-check`](clear-check.md) | Direct verdict on whether it's **safe to `/clear`** the context now, with a wrap-up checklist if not. |

Unlike the [CLAUDE.md partials](../README.md), slash commands **cannot** be
`@`-imported — they must physically live in `~/.claude/commands/`. So integration
is a symlink (or copy) rather than an import line.

## Setup in a new environment

Clone the repo somewhere stable (if not already), then run the installer:

```bash
git clone https://github.com/freaxnx01/config.git ~/repos/github/freaxnx01/public/config   # if needed
~/repos/github/freaxnx01/public/config/claude/commands/install.sh        # symlink (default)
```

- **Symlink mode (default)** — `~/.claude/commands/<cmd>.md` points back at this
  repo, so a `git pull` here updates every machine instantly. Best on WSL2/Linux/macOS.
- **Copy mode** — `install.sh --copy`. Use on native Windows or anywhere symlinks
  are awkward; re-run after pulling updates.

### Native Windows (PowerShell, no symlinks)

```powershell
Copy-Item -Force "$HOME\repos\...\config\claude\commands\*.md" "$HOME\.claude\commands\"
```

## Verify

Start a **new** session (or it may already be picked up) and type `/` — both
commands should appear in the menu. Run `/clear-check` to confirm it responds.

## Adding a command

Drop a new `<name>.md` here with a `description:` front-matter, commit, and re-run
`install.sh` on each machine. That's it.
