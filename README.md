# freaxnx01/config

Version-controlled, cross-machine **Claude Code** configuration — CLAUDE.md
partials, slash commands, and hooks — plus other personal config (oh-my-posh,
Windows). Public, so any machine can pull it with no auth.

## Set up a new machine (one URL)

On Linux / macOS / WSL2, run:

```bash
curl -fsSL https://raw.githubusercontent.com/freaxnx01/config/main/setup/bootstrap.sh | bash
```

That clones this repo to `~/repos/github/freaxnx01/public/config` and runs all
setup steps idempotently:

| Step | Script | Installs |
|------|--------|----------|
| Partials | [`setup/00-claude-partials.sh`](setup/00-claude-partials.sh) | `@`-imports into `~/.claude/CLAUDE.md` (task-checklist, skill-authoring, subagent-driven-default) |
| Commands | [`setup/01-claude-commands.sh`](setup/01-claude-commands.sh) | Generic slash commands from this repo **plus** the issue-workflow console from [agent-workflow](https://github.com/freaxnx01/agent-workflow) (cloned + linked automatically) into `~/.claude/commands/` — see [list](claude/commands/README.md) |
| Hooks | [`setup/02-claude-hooks.sh`](setup/02-claude-hooks.sh) | `handoff-resume` SessionStart(clear) hook + `settings.json` wiring |

**Requirements:** `git` and `jq` (the handoff hook needs `jq` at runtime). Commands
are symlinked, so later updates are just `git -C ~/repos/github/freaxnx01/public/config pull`.

### Filesystems without symlinks (e.g. some Windows setups)

```bash
curl -fsSL https://raw.githubusercontent.com/freaxnx01/config/main/setup/bootstrap.sh | bash -s -- --copy
```

Native Windows (PowerShell, no WSL) isn't fully scripted yet — the bash setup
won't run and the handoff hook needs a PowerShell port (tracked in
[#31](https://github.com/freaxnx01/config/issues/31)). Until then, copy the command
`.md` files into `%USERPROFILE%\.claude\commands\` and add the partial `@`-imports
to `%USERPROFILE%\.claude\CLAUDE.md` by hand.

### Run individual steps

Each step is also independently curl-bootstrappable, e.g.:

```bash
curl -fsSL https://raw.githubusercontent.com/freaxnx01/config/main/setup/01-claude-commands.sh | bash
```

## Verify

Start a fresh Claude Code session, then:

- `/commands` — lists all installed custom commands
- `/memory` — partials appear nested under your user `CLAUDE.md`

## What's here

- [`claude/`](claude/) — partials, generic [commands](claude/commands/README.md), and [hooks](claude/hooks/)
  (the issue-workflow console commands live in [agent-workflow](https://github.com/freaxnx01/agent-workflow)`/commands/`, installed by the same bootstrap)
- [`setup/`](setup/) — the idempotent installers above
- `oh-my-posh/`, `windows/` — other personal config

Commits use [Conventional Commits](https://www.conventionalcommits.org/).
