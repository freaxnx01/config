# freaxnx01/config

Version-controlled, cross-machine **Claude Code** configuration — CLAUDE.md
partials — plus other personal config (oh-my-posh,
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
| Commands | [`setup/01-claude-commands.sh`](setup/01-claude-commands.sh) | All 46 user-level slash commands from [agent-workflow](https://github.com/freaxnx01/agent-workflow) (cloned + installed automatically) into `~/.claude/commands/` — see [list](https://github.com/freaxnx01/agent-workflow/blob/main/commands/README.md) |
| Hooks | [`setup/02-claude-hooks.sh`](setup/02-claude-hooks.sh) | `handoff-resume` SessionStart(clear) hook from [agent-workflow](https://github.com/freaxnx01/agent-workflow) + `settings.json` wiring |

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

- [`claude/`](claude/) — CLAUDE.md partials only. As of 2026-07-21 every slash
  command and hook lives in [agent-workflow](https://github.com/freaxnx01/agent-workflow)
  (`commands/`, `hooks/`), installed by this repo's bootstrap.
- [`setup/`](setup/) — the idempotent installers above
- `oh-my-posh/`, `windows/` — other personal config

Commits use [Conventional Commits](https://www.conventionalcommits.org/).
