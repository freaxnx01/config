# Claude Code shared slash commands

User-level [custom slash commands](https://docs.anthropic.com/en/docs/claude-code/slash-commands#custom-slash-commands)
for Claude Code. Each `.md` file becomes a `/<filename>` command (subdirs become
`/namespace:command`); the `description:` front-matter shows in the `/`
autocomplete menu.

> **Where the issue-workflow console went.** The forge routers (`/issues`,
> `/enrich`, `/route`, `/work`, …) and the `gh:*` / `fj:*` families now live in
> **[freaxnx01/agent-workflow](https://github.com/freaxnx01/agent-pipeline)** under
> its top-level `commands/` — they are the pipeline's operator console. config's
> bootstrap still installs them (it clones agent-workflow and calls its link step),
> so `/commands` lists everything regardless of origin. This README covers only the
> generic Claude Code commands that remain in config.

## At a glance

**Meta**
- `/commands` — list my custom slash commands (user + project), grouped
- `/update-commands` — update user-level commands from **both** sources (config + agent-workflow): pull + relink

**Session hygiene**
- `/loose-ends` — list anything started but unfinished
- `/clear-check` — verdict on whether it's safe to `/clear`
- `/wrap-up` → `/todo` — whole-session loose-ends checklist (committed to `TODO.md`)

**Phase handoff** (pairs with the `SessionStart(clear)` [hook](../hooks/handoff-resume.sh))
- `/handoff` — save spec/plan to MD + resume prompt to `.claude/handoff.md` + clipboard, then `/clear`
- `/pickup` — resume from `.claude/handoff.md`

**Superpowers**
- `/subagent-driven` — execute the current plan subagent-driven (pairs with the always-on [`subagent-driven-default`](../subagent-driven-default.md) partial)

**Worktree** (`wt/`)
- `/wt:status` — git status: uncommitted/untracked, branches, worktrees, cleanup check
- `/wt:finish` — commit, merge, clean up the worktree

Full details below.

| Command | What it does |
|---------|--------------|
| [`/commands`](commands.md) | Lists your custom slash commands (user + project), grouped by source and namespace. |
| [`/update-commands`](update-commands.md) | Updates user-level commands from **both** config and agent-workflow — pulls latest `main` and re-symlinks into `~/.claude/commands/`. Read-only; no auth. |
| [`/loose-ends`](loose-ends.md) | Lists anything started but not finished in the session — uncommitted edits, unrun/failing tests, queued commands, open follow-ups. |
| [`/clear-check`](clear-check.md) | Direct verdict on whether it's **safe to `/clear`** the context now, with a wrap-up checklist if not. |
| [`/handoff`](handoff.md) | Saves the current spec/plan to an MD file and writes a resume prompt (with the file path) to `.claude/handoff.md` + clipboard, so you can `/clear` and continue cold. |
| [`/pickup`](pickup.md) | Resumes work saved by `/handoff` — reads `.claude/handoff.md` and continues from where you left off, subagent-driven. |
| [`/subagent-driven`](subagent-driven.md) | Executes the current implementation plan via `superpowers:subagent-driven-development`. Explicit counterpart to the always-on [`subagent-driven-default`](../subagent-driven-default.md) partial. |
| [`/wt:status`](wt/status.md) | Read-only: uncommitted/untracked files, branches (merged + ahead/behind), worktrees, and a verdict on whether the current worktree is safe to clean up. |
| [`/wt:finish`](wt/finish.md) | Commit, merge into default branch, and clean up the current worktree/branch (confirms before destructive steps). |

### When to use which save-and-resume pair

Both pairs persist state to a file so work can resume later, so they look
redundant — but they answer different questions and are **both kept on purpose**:

- **`/wrap-up` → `/todo`** — *"what were all the threads I left dangling?"* A
  whole-session, multi-topic checklist. `/wrap-up` writes `TODO.md` at the repo root
  and **commits & pushes** it; `/todo` reads it back, shows the unchecked items, and
  asks which to tackle. Because `TODO.md` is committed, it survives across machines.
- **`/handoff` → `/pickup`** — *"I'm deep in one task and need to `/clear` without
  losing my place."* A single in-flight phase artifact (the current spec or plan).
  `/handoff` writes `.claude/handoff.md` + copies a resume prompt to the clipboard;
  `/pickup` continues that one task from the exact next step, subagent-driven. It
  pairs with the `SessionStart(clear)` hook below.

| Axis | `/wrap-up` → `/todo` | `/handoff` → `/pickup` |
|---|---|---|
| Granularity | many loose ends across the session | one in-flight phase artifact |
| Boundary | end-of-session / next-day resume | mid-task `/clear` to shed context bloat |
| Saved to & travel | `TODO.md` at repo root — committed & pushed → cross-machine | `.claude/handoff.md` — local + clipboard, not committed → same-machine |
| Automation | none | `SessionStart(clear)` handoff-resume hook |
| Resume style | checklist, pick an item | continue one task from the next step |

> `.claude/handoff.md` is intentionally local/ephemeral today; making it syncable
> across machines is tracked separately in issue #34.

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
clones (or pulls) the repo at the canonical path, installs these generic commands
into `~/.claude/commands/`, **and** clones agent-workflow to install the console
commands:

```bash
curl -fsSL https://raw.githubusercontent.com/freaxnx01/config/main/setup/01-claude-commands.sh | bash
```

(Or, if you've already cloned the repo, run
`~/repos/github/freaxnx01/public/config/setup/01-claude-commands.sh`.)

- **Symlink mode (default)** — `~/.claude/commands/<cmd>.md` points back at the
  source repo, so a `git pull` there updates every machine instantly. Best on WSL2/Linux/macOS.
- **Copy mode** — pass `--copy`. Use on native Windows or anywhere symlinks are
  awkward; re-run after pulling updates. (Copies from **both** source repos.)
- **`--no-sync`** — relink from the current working trees without pulling.

### Native Windows (PowerShell, no symlinks)

```powershell
Copy-Item -Recurse -Force "$HOME\repos\...\config\claude\commands\*.md" "$HOME\.claude\commands\"
Copy-Item -Recurse -Force "$HOME\repos\...\agent-pipeline\commands\*" "$HOME\.claude\commands\"
```

## Verify

Start a **new** session (or it may already be picked up) and type `/` — commands
should appear in the menu. Run `/clear-check` to confirm it responds.

## Adding a command

A generic Claude Code command goes here; an issue-workflow / pipeline command goes in
`agent-pipeline/commands/`. Drop a new `<name>.md` with a `description:` front-matter,
commit, and re-run the matching linker on each machine.
