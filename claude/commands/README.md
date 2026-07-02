# Claude Code shared slash commands

User-level [custom slash commands](https://docs.anthropic.com/en/docs/claude-code/slash-commands#custom-slash-commands)
for Claude Code. Each `.md` file becomes a `/<filename>` command (subdirs become
`/namespace:command`); the `description:` front-matter shows in the `/`
autocomplete menu.

## At a glance

**Meta**
- `/commands` — list my custom slash commands (user + project), grouped
- `/update-commands` — update these user-level commands from the config repo (pull + relink)

**Session hygiene**
- `/loose-ends` — list anything started but unfinished
- `/clear-check` — verdict on whether it's safe to `/clear`

**Phase handoff** (pairs with the `SessionStart(clear)` [hook](../hooks/handoff-resume.sh))
- `/handoff` — save spec/plan to MD + resume prompt to `.claude/handoff.md` + clipboard, then `/clear`
- `/pickup` — resume from `.claude/handoff.md`

**Superpowers**
- `/subagent-driven` — execute the current plan subagent-driven (pairs with the always-on [`subagent-driven-default`](../subagent-driven-default.md) partial)

**Forge routers** (auto-detect GitHub vs Forgejo from the `origin` remote, then delegate to the `gh:`/`fj:` pair)
- `/issues` — open issues, newest first
- `/prs` — PRs awaiting review
- `/parked` — parked (🧊) issues, newest first
- `/triage` — open issues: bugs/fixes first, then quick wins
- `/done` — recently implemented (closed) issues
- `/new <notes>` — create issue, labeled `needs-enrichment`
- `/enrich <N>` — enrich issue with spec + plan
- `/enrich-phased <N>` — phased enrich (spec → `/clear` → plan → `/clear` → body)
- `/route <N>` — recommend implementation path by complexity & readiness
- `/work <N>` — work issue #N end-to-end (**TDD enforced**)

**GitHub** (`gh/`)
- `/gh:new <notes>` — create issue, labeled `needs-enrichment`
- `/gh:issues` — open issues, newest first
- `/gh:parked` — parked (🧊) issues, newest first
- `/gh:triage` — open issues: bugs/fixes first, then quick wins
- `/gh:enrich <N>` — enrich issue with spec + plan, update body for agent-pipeline
- `/gh:enrich-phased <N>` — phased `/gh:enrich`: spec → `/clear` → plan → `/clear` → issue body (isolated context per phase)
- `/gh:route <N>` — recommend implementation path (work / assign / implement) by complexity & readiness
- `/gh:work <N>` — work issue #N (view → plan → worktree → subagent-driven, **TDD enforced**)
- `/gh:assign <N> [copilot|claude]` — assign issue to a coding agent (**posts TDD contract** before assigning)
- `/gh:implement <N>` — validate readiness, label `ai-implement` to trigger agent-pipeline (**posts TDD contract** before labeling)
- `/gh:prs` — PRs awaiting review
- `/gh:review [N…]` — pre-review PRs vs their issue AC, then trigger `@copilot`/`@claude` to fix
- `/gh:done` — recently implemented (closed) issues

**Worktree** (`wt/`)
- `/wt:status` — git status: uncommitted/untracked, branches, worktrees, cleanup check
- `/wt:finish` — commit, merge, clean up the worktree

Full details below.

| Command | What it does |
|---------|--------------|
| [`/commands`](commands.md) | Lists your custom slash commands (user + project), grouped by source and namespace. |
| [`/update-commands`](update-commands.md) | Updates these user-level commands from the config repo — pulls latest `main` and re-symlinks into `~/.claude/commands/` via `setup/01-claude-commands.sh`. Read-only; no auth. |
| [`/loose-ends`](loose-ends.md) | Lists anything started but not finished in the session — uncommitted edits, unrun/failing tests, queued commands, open follow-ups. |
| [`/clear-check`](clear-check.md) | Direct verdict on whether it's **safe to `/clear`** the context now, with a wrap-up checklist if not. |
| [`/handoff`](handoff.md) | Saves the current spec/plan to an MD file and writes a resume prompt (with the file path) to `.claude/handoff.md` + clipboard, so you can `/clear` and continue cold. |
| [`/pickup`](pickup.md) | Resumes work saved by `/handoff` — reads `.claude/handoff.md` and continues from where you left off, subagent-driven. |
| [`/subagent-driven`](subagent-driven.md) | Executes the current implementation plan via `superpowers:subagent-driven-development`. Explicit counterpart to the always-on [`subagent-driven-default`](../subagent-driven-default.md) partial. |

### Forge routers (`/issues`, `/prs`, `/parked`, `/triage`, `/done`)

Forge-agnostic aliases. Each detects the forge from the `origin` remote host —
generic host-matching against `gh auth` logins (GitHub / GHES) and `tea logins`
(Forgejo / Gitea), falling back to `github.com` — then reads and follows the
matching `gh:`/`fj:` command, which stays the single source of truth for the query.
Unknown host → it reports the host and points at `gh auth login` / `tea login add`
rather than guessing.

| Command | What it does |
|---------|--------------|
| [`/issues`](issues.md) | → `/gh:issues` or `/fj:issues` — open issues, newest first (not WIP, not parked). |
| [`/prs`](prs.md) | → `/gh:prs` or `/fj:prs` — PRs awaiting review. |
| [`/parked`](parked.md) | → `/gh:parked` or `/fj:parked` — parked (🧊) issues, newest first. |
| [`/triage`](triage.md) | → `/gh:triage` or `/fj:triage` — open issues: bugs/fixes first, then quick wins. |
| [`/done`](done.md) | → `/gh:done` or `/fj:done` — recently implemented (closed) issues. |
| [`/new`](new.md) `<notes>` | → `/gh:new` or `/fj:new` — create an issue from notes, labeled `needs-enrichment`. |
| [`/enrich`](enrich.md) `<N>` | → `/gh:enrich` or `/fj:enrich` — enrich issue #N with a spec + implementation plan. |
| [`/enrich-phased`](enrich-phased.md) `<N>` | → `/gh:enrich-phased` or `/fj:enrich-phased` — phased enrichment with context isolation. |
| [`/route`](route.md) `<N>` | → `/gh:route` or `/fj:route` — recommend the implementation path for issue #N. |
| [`/work`](work.md) `<N>` | → `/gh:work` or `/fj:work` — work issue #N end-to-end (**TDD enforced**). |

`/assign`, `/implement`, and `/review` have **no router** — they're GitHub-only
(agent-pipeline / coding-agent triggers with no Forgejo equivalent). Use the `gh:`
form directly.

### GitHub & worktree workflow (`gh/`, `wt/`)

Namespaced via subdirectories — `gh/new.md` → `/gh:new`, `wt/finish.md` →
`/wt:finish`. All use the `gh` CLI against the current repo (whatever your active
`gh` account can access).

| Command | What it does |
|---------|--------------|
| [`/gh:new`](gh/new.md) `<notes>` | Creates an issue from your notes, always labeled `needs-enrichment` (creates the label if missing). |
| [`/gh:issues`](gh/issues.md) | Open issues, newest first — compact table. Excludes parked and WIP (open PR) issues. |
| [`/gh:parked`](gh/parked.md) | Open issues carrying `🧊 parked` — intentionally deferred — newest first. |
| [`/gh:triage`](gh/triage.md) | Open issues ordered for triage: bugs/fixes first, then low-complexity quick wins. |
| [`/gh:enrich`](gh/enrich.md) `<N>` | Enriches issue #N with a spec and implementation plan, then updates the issue body so it's ready for the agent-pipeline. |
| [`/gh:enrich-phased`](gh/enrich-phased.md) `<N>` | Phased enrichment with context isolation: spec phase → `/clear` → plan phase → `/clear` → update issue body. Use when the issue is complex enough that a single context window isn't enough. |
| [`/gh:route`](gh/route.md) `<N>` | Recommends the best implementation path for issue #N — `/gh:work`, `/gh:assign copilot\|claude`, or `/gh:implement` with an agent-pipeline model — based on complexity and readiness. |
| [`/gh:work`](gh/work.md) `<N>` | Works issue #N end-to-end: view → brainstorm (if unclear) → plan → worktree → subagent-driven implementation → ready for `/wt:finish`. **TDD is a non-negotiable global constraint** injected into the plan. |
| [`/gh:assign`](gh/assign.md) `<N> [copilot\|claude]` | Assigns issue #N to a GitHub coding agent (defaults to `@copilot`). **Posts a TDD contract comment** on the issue before assigning so the bot reads it as context. |
| [`/gh:implement`](gh/implement.md) `<N>` | Validates issue readiness (AC, scope, no blocking unknowns), then labels it `ai-implement` to trigger the agent-pipeline. **Posts a TDD contract comment** on the issue before labeling. |
| [`/gh:prs`](gh/prs.md) | Open PRs awaiting review (yours-requested first, then others not slipping through). |
| [`/gh:review`](gh/review.md) `[N…]` | Pre-reviews PR(s) against their linked issue's acceptance criteria (parallel reviewer per PR), posts a comment-type review, and — only when fixes are needed — pings the owning agent with a numbered fix list. Prefers `@copilot` (the reliable trigger; can take over Claude-opened PRs too); uses `@claude` only where the Anthropic agent is confirmed responsive. |
| [`/gh:done`](gh/done.md) | Recently implemented (closed-as-completed) issues, most recent first. |
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
