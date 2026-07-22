# freaxnx01/config

Version-controlled, cross-machine **machine setup** — shell, the
[oh-my-posh](https://ohmyposh.dev/) prompt, and Windows tooling. Public, so any
machine can pull it with no auth.

> **Looking for Claude Code configuration?** As of **2026-07-21** all Claude
> content *and* its provisioning — the `CLAUDE.md` partials, the slash commands,
> the hooks, and the skills, plus the one-URL bootstrap that installs them — live
> in [**freaxnx01/agent-workflow**](https://github.com/freaxnx01/agent-workflow)
> (ADR-007 there). Set up a machine with:
>
> ```bash
> curl -fsSL https://raw.githubusercontent.com/freaxnx01/agent-workflow/main/setup/bootstrap.sh | bash
> ```
>
> The old `config` bootstrap URL still works — [`setup/bootstrap.sh`](setup/bootstrap.sh)
> is now a thin deprecation stub that forwards to the URL above (passing your
> arguments through) and prints the new bookmark. Update your notes when you can.

## What's here

- `oh-my-posh/` — prompt theme(s) and configuration
- `windows/` — Windows-specific tooling and config
- [`setup/bootstrap.sh`](setup/bootstrap.sh) — deprecation stub that forwards to
  agent-workflow (see the note above)

These are installed manually for now; there is no combined installer.

Commits use [Conventional Commits](https://www.conventionalcommits.org/).
