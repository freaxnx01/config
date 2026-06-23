# Claude Code shared slash commands

User-level [custom slash commands](https://docs.anthropic.com/en/docs/claude-code/slash-commands#custom-slash-commands)
for Claude Code. Each `.md` file becomes a `/<filename>` command; the
`description:` front-matter shows in the `/` autocomplete menu.

| Command | What it does |
|---------|--------------|
| [`/loose-ends`](loose-ends.md) | Lists anything started but not finished in the session — uncommitted edits, unrun/failing tests, queued commands, open follow-ups. |
| [`/clear-check`](clear-check.md) | Direct verdict on whether it's **safe to `/clear`** the context now, with a wrap-up checklist if not. |
| [`/handoff`](handoff.md) | Saves the current spec/plan to an MD file and writes a resume prompt (with the file path) to `.claude/handoff.md` + clipboard, so you can `/clear` and continue cold. |
| [`/pickup`](pickup.md) | Resumes work saved by `/handoff` — reads `.claude/handoff.md` and continues from where you left off, subagent-driven. |
| [`/subagent-driven`](subagent-driven.md) | Executes the current implementation plan via `superpowers:subagent-driven-development`. Explicit counterpart to the always-on [`subagent-driven-default`](../subagent-driven-default.md) partial. |

### The `/handoff` → `/clear` → `/pickup` flow

A skill **cannot** run `/clear` or inject a follow-up prompt itself — clearing
context and starting a new turn are harness actions driven by your keystrokes, not
by model output. So the phase handoff is two commands with a manual `/clear`
between them:

1. `/handoff` — persists the artifact, writes `.claude/handoff.md`, copies the
   resume prompt to your clipboard.
2. `/clear` — you type this.
3. `/pickup` — reads `.claude/handoff.md` and continues. (Or just paste the
   clipboard.)

**Optional auto-surface hook.** [`../hooks/handoff-resume.sh`](../hooks/handoff-resume.sh)
is a `SessionStart(clear)` hook: when you `/clear`, it injects `.claude/handoff.md`
as context automatically, so the resume prompt is already loaded (you just type
`/pickup` or "go"). Install the script to `~/.claude/hooks/` and add to
`~/.claude/settings.json`:

```json
{ "hooks": { "SessionStart": [
  { "matcher": "clear", "hooks": [
    { "type": "command", "command": "$HOME/.claude/hooks/handoff-resume.sh" }
  ] }
] } }
```

(Merge into any existing `SessionStart` block — don't replace it.) A command/skill
cannot run `/clear` or auto-send a prompt itself, so this passive injection is as
close to "auto-resume" as the harness allows.

Unlike the [CLAUDE.md partials](../README.md), slash commands **cannot** be
`@`-imported — they must physically live in `~/.claude/commands/`. So integration
is a symlink (or copy) rather than an import line.

## Setup in a new environment

### Recommended — one command

The repo ships an idempotent setup script (sibling to the partials installer) that
clones (or pulls) the repo at the canonical path AND installs these commands into
`~/.claude/commands/`:

```bash
curl -fsSL https://raw.githubusercontent.com/freaxnx01/config/main/setup/01-claude-commands.sh | bash
```

(Or, if you've already cloned the repo, run
`~/repos/github/freaxnx01/public/config/setup/01-claude-commands.sh`.)

- **Symlink mode (default)** — `~/.claude/commands/<cmd>.md` points back at this
  repo, so a `git pull` here updates every machine instantly. Best on WSL2/Linux/macOS.
- **Copy mode** — pass `--copy`. Use on native Windows or anywhere symlinks are
  awkward; re-run after pulling updates.

### Native Windows (PowerShell, no symlinks)

```powershell
Copy-Item -Force "$HOME\repos\...\config\claude\commands\*.md" "$HOME\.claude\commands\"
```

## Verify

Start a **new** session (or it may already be picked up) and type `/` — both
commands should appear in the menu. Run `/clear-check` to confirm it responds.

## Adding a command

Drop a new `<name>.md` here with a `description:` front-matter, commit, and re-run
`setup/01-claude-commands.sh` on each machine. That's it.
