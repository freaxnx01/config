# Move the issue-workflow slash commands out of `config` into `agent-pipeline`

**Date:** 2026-07-12
**Status:** Approved design — ready for implementation plan
**Repos touched:** `freaxnx01/config`, `freaxnx01/agent-pipeline`

## Problem

`config` describes itself as "version-controlled Claude Code **configuration** —
CLAUDE.md partials, slash commands, and hooks." In practice `claude/commands/` has
grown into a full issue-lifecycle **toolkit** (~40 command files: `gh:*`, `fj:*`,
forge routers, `enrich`, `route`, `implement`, `work`, …). That toolkit is the
human-facing front-end of a *separate* system, `agent-pipeline`, which today only
receives a trigger (`/gh:implement` labels an issue `ai-implement`; CI in
`agent-pipeline` opens the draft PR).

The commands feed and drive the pipeline but live in a repo scoped to "config." The
owner's read: **config is being misused as a home for what is really the pipeline's
operator console.**

## Key insight that shapes the design

`agent-pipeline` is **intended to become forge-agnostic** — Claude Code in GitHub
Actions today, Forgejo Actions later. Under that north star:

- The `fj:*` (Forgejo) commands are **not** foreign to the pipeline. They are the
  Forgejo half of the same product, waiting for the CI side to catch up.
- The forge-agnostic routers (`/issues`, `/enrich`, `/route`, `/work`, …) and both
  `gh:*`/`fj:*` families together **are** the pipeline's local operator console —
  present (GitHub) and future (Forgejo).

This makes "move the issue-workflow commands into `agent-pipeline`" coherent, on one
condition (see §1): `agent-pipeline` must be reconceived as **the pipeline
end-to-end** — its CI side *and* its local console — not "the CI side only."

## Non-goals

- No change to the pipeline's runtime behavior, CI workflows, or trigger mechanism.
- No change to command *logic* — this is a relocation + install/doc refactor.
- Not building the Forgejo Actions CI side (that catches up later); we only make the
  command home ready for it.
- No unrelated refactoring of the commands themselves.

## Design

### 1. Reconception (prerequisite framing)

`agent-pipeline/docs/DESIGN.md` currently states `agent-pipeline = the CI side
(workflows, scripts, fixtures, docs)`. Widen that boundary to:

> **agent-pipeline = the pipeline end-to-end**: the CI side (`.github/workflows`,
> `scripts`, fixtures, docs) **plus** the human-facing operator console (the
> user-level slash commands you drive it with), forge-agnostic across GitHub Actions
> (now) and Forgejo Actions (later).

Without this reframing the move merely relocates the same "wrong repo" smell.
Update `DESIGN.md` and add a boundary note to `DECISIONS.md`.

### 2. Partition — what moves vs. stays

**→ Move to `agent-pipeline`** (the forge/issue-workflow console):

| Group | Commands |
|---|---|
| Top-level routers | `issues`, `prs`, `parked`, `triage`, `done`, `new`, `enrich`, `enrich-phased`, `route`, `work`, `capture-idea` |
| `gh/` (all 13) | `new`, `issues`, `parked`, `triage`, `enrich`, `enrich-phased`, `route`, `work`, `assign`, `implement`, `prs`, `review`, `done` |
| `fj/` (all 10) | `new`, `issues`, `parked`, `triage`, `enrich`, `enrich-phased`, `route`, `work`, `prs`, `done` |

**⏹ Stay in `config`** (genuinely Claude Code config, not the pipeline):

| Group | Commands |
|---|---|
| Session hygiene | `handoff`, `pickup`, `loose-ends`, `clear-check`, `wrap-up`, `todo` |
| Superpowers | `subagent-driven` |
| Meta | `commands`, `update-commands` |
| Worktree | `wt:status`, `wt:finish` |

Resolved judgment calls:
- **`wt:*` stays in config** — generic git worktree hygiene, forge-agnostic, not
  pipeline-specific (even though `work` pairs with it).
- **`capture-idea` moves** — it is the mouth of the issue funnel; it belongs with the
  funnel it feeds.

### 3. Install mechanics

The moved commands are **user-level** — symlinked into `~/.claude/commands/` so they
work from *any* repo. This is different from `agent-pipeline`'s existing
`.claude/commands/` (`commit`, `push`, `ui-*`), which are **project-scoped** (active
only inside that repo). Implications:

1. `agent-pipeline` grows a **new top-level `commands/`** directory — user-level,
   deliberately distinct from its project-scoped `.claude/commands/`. (Namespacing:
   `gh/` and `fj/` subdirs preserved so `/gh:enrich` etc. keep their names.)
2. **`config` stays the single "one-URL" machine bootstrap.** Its bootstrap remains
   the orchestrator: it clones `agent-pipeline` if absent and links that repo's
   `commands/` into `~/.claude/commands/` too — so the "one curl sets up a machine"
   promise survives. `agent-pipeline` exposes a small link step that config's setup
   calls; it does **not** grow a competing bootstrap.
3. `config/setup/01-claude-commands.sh` is re-pointed to link only the retained
   (generic) commands from `config`, then invoke `agent-pipeline`'s link step for the
   console commands.
4. `/update-commands` learns **two sources** — pull + relink both `config` and
   `agent-pipeline`. `/commands` needs no change (it lists `~/.claude/commands/`
   regardless of origin).

**Resolved (2026-07-12):** `agent-pipeline`'s link step is a **thin script under
`agent-pipeline/setup/`** (mirroring config's pattern) that config's `01-` script
invokes. The source repo owns knowledge of its own layout; config does not hardcode
`agent-pipeline`'s `commands/` path.

### 4. Docs & cutover

- **Copy** the command files into `agent-pipeline/commands/` and `git rm` them from
  `config` (resolved 2026-07-12 — pragmatic copy over a cross-repo history graft).
  Per-file history stays reachable in config's git log; agent-pipeline starts them
  fresh with a provenance note in the commit message.
- Update READMEs: `config`'s root "What's here" + `claude/commands/README.md`;
  `agent-pipeline`'s README + `docs/DESIGN.md` + `docs/DECISIONS.md` boundary note.
- Fix all cross-references (both repos reference the moved commands).
- Re-point `config/setup/01-claude-commands.sh`.
- Land as **one coordinated change across both repos** (two PRs that merge together,
  or a documented order) so no machine is left with dangling symlinks between steps.

## Blast radius / risks

- **Dangling symlinks** during cutover if config links to files that have moved.
  Mitigation: land both repos together; `update-commands` re-runs the linker.
- **"One-URL" bootstrap** now depends on cloning a second repo. Mitigation: config's
  bootstrap clones `agent-pipeline` idempotently; failure is surfaced, not silent.
- **Windows/no-symlink path** (`--copy` mode, tracked in config #31) must copy from
  both source repos now. Note it; don't regress it.
- **`agent-pipeline` gains a user-level surface** it didn't have — its README/DESIGN
  must make the `commands/` (user-level) vs `.claude/commands/` (project) distinction
  explicit so future contributors don't conflate them.

## Success criteria

1. From a fresh machine, one `curl … bootstrap.sh | bash` still yields all commands
   in `~/.claude/commands/` — console commands sourced from `agent-pipeline`, generic
   ones from `config`.
2. `/gh:enrich`, `/fj:enrich`, `/route`, `/work`, `/capture-idea` etc. run identically
   to before, from any repo.
3. `config/claude/commands/` contains only the retained generic set; its README
   reflects that.
4. `agent-pipeline` owns the console commands, with README/DESIGN updated to the
   forge-agnostic "CI + console" framing.
5. No dangling symlinks; `/update-commands` refreshes both sources.
