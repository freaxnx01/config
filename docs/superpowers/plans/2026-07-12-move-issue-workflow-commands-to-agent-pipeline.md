# Move Issue-Workflow Slash Commands to agent-pipeline — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Relocate the ~34 issue-workflow operator-console slash commands (top-level forge routers + all `gh:*` + all `fj:*`) out of `config` into `agent-pipeline`, and rewire the install/docs so a single bootstrap still lands every command in `~/.claude/commands/`.

**Architecture:** `agent-pipeline` grows a **new top-level `commands/` directory** (user-level console, distinct from its existing project-scoped `.claude/commands/`) plus a thin `setup/link-commands.sh` linker that mirrors config's pattern. `config` stays the single "one-URL" bootstrap orchestrator: its `setup/01-claude-commands.sh` links the retained generic commands, then clones `agent-pipeline` (if absent) and invokes `agent-pipeline`'s link step. Files are **copied** into `agent-pipeline` and `git rm`'d from `config` (per-file history stays reachable in config's log — no cross-repo history graft).

**Tech Stack:** Bash setup scripts (`set -euo pipefail`), Claude Code user-level slash commands (`.md` files under `~/.claude/commands/`, subdirs → `/namespace:cmd`), Markdown docs. No compiled code, no unit-test framework — verification is deterministic sandbox runs of the linkers asserting symlink resolution and absence of dangling links.

## Global Constraints

- **Both repos live at** `~/repos/github/freaxnx01/public/{config,agent-pipeline}`. Use `$HOME/repos/github/freaxnx01/public/...` in scripts (never absolute `/home/...`).
- **No change to command *logic*.** This is a relocation + install/doc refactor. Command `.md` bodies move byte-for-byte (verified by `diff`). The only prose edits allowed to a moved file are none — bodies are copied verbatim.
- **No change to pipeline runtime, CI workflows, or the trigger mechanism.**
- **Idempotent installers.** Every setup script must be safe to re-run. Default install mode is **symlink**; `--copy` mode must keep working (Windows/no-symlink path, config #31).
- **New `--no-sync` flag** on both linkers skips the clone/pull and just (re)links from the current working tree. Used by verification and by config's linker when it has already synced. Default (flag absent) = sync as today.
- **Zero dangling symlinks** at every committed state that a machine could install from.
- **Namespacing preserved:** `commands/gh/` and `commands/fj/` subdirs keep `/gh:*` and `/fj:*` command names intact.
- **READMEs are skipped by linkers** (`README.md` at top level or inside namespace dirs) — safe to place index READMEs anywhere under `commands/`.
- **Commit convention:** Conventional Commits (`feat(scope): …`, `refactor(scope): …`, `docs(scope): …`).
- **Landing order (cross-repo):** push/merge **agent-pipeline first** (files + link step exist), **then config** (which removes the files and points at agent-pipeline). Never the reverse — a machine that pulls config first would lose the console until agent-pipeline lands.

### The 34 commands that MOVE (config/claude/commands → agent-pipeline/commands)

- **Top-level routers (11):** `issues`, `prs`, `parked`, `triage`, `done`, `new`, `enrich`, `enrich-phased`, `route`, `work`, `capture-idea`
- **`gh/` (13):** `new`, `issues`, `parked`, `triage`, `enrich`, `enrich-phased`, `route`, `work`, `assign`, `implement`, `prs`, `review`, `done`
- **`fj/` (10):** `new`, `issues`, `parked`, `triage`, `enrich`, `enrich-phased`, `route`, `work`, `prs`, `done`

### The 11 commands that STAY in config/claude/commands

- **Top-level (9):** `clear-check`, `commands`, `handoff`, `loose-ends`, `pickup`, `subagent-driven`, `todo`, `update-commands`, `wrap-up`
- **`wt/` (2):** `status`, `finish`
- Plus the rewritten `README.md`.

### Reusable verification harness (referenced by Tasks 2, 4, 5, 7)

Runs a linker in an isolated sandbox `HOME` with `--no-sync`, so no network clone and no `git pull` on the feature branch — links resolve into the **local working trees** via pre-seeded symlinks. Non-destructive to the real `~/.claude/commands/`.

```bash
# harness.sh — save under scratchpad while implementing; NOT committed.
SB="$(mktemp -d)"
mkdir -p "$SB/repos/github/freaxnx01/public"
ln -s "$HOME/repos/github/freaxnx01/public/config"         "$SB/repos/github/freaxnx01/public/config"
ln -s "$HOME/repos/github/freaxnx01/public/agent-pipeline" "$SB/repos/github/freaxnx01/public/agent-pipeline"

# $1 = linker path (relative to a repo under $SB), extra args follow
HOME="$SB" bash "$SB/repos/github/freaxnx01/public/$1" "${@:2}"

echo "== total command .md installed =="
find "$SB/.claude/commands" \( -type f -o -type l \) -name '*.md' | wc -l
echo "== broken symlinks (MUST be empty) =="
find "$SB/.claude/commands" -type l ! -exec test -e {} \; -print
echo "== resolved sources (sample) =="
for c in gh/enrich.md fj/work.md route.md capture-idea.md handoff.md wt/status.md; do
  [ -e "$SB/.claude/commands/$c" ] && printf '  %-18s -> %s\n' "$c" "$(readlink -f "$SB/.claude/commands/$c")"
done
rm -rf "$SB"
```

---

## File Structure

**Created in `agent-pipeline`:**
- `commands/` — 34 user-level console command `.md` files (11 top-level + `gh/` 13 + `fj/` 10), copied verbatim from config.
- `commands/README.md` — console index (linker skips it).
- `setup/link-commands.sh` — thin user-level linker (symlink default, `--copy`, `--no-sync`).

**Modified in `agent-pipeline`:**
- `docs/DESIGN.md` — widen the boundary statement (line 31 + Scope).
- `docs/DECISIONS.md` — add ADR-005 (console boundary + user-level vs project-scoped distinction).

**Modified in `config`:**
- `setup/01-claude-commands.sh` — link retained generic commands, then clone-if-absent + invoke agent-pipeline's linker; add `--no-sync`.
- `claude/commands/README.md` — trim to the retained set; point at agent-pipeline for the console.
- `claude/commands/update-commands.md` — learn two sources (pull + relink both repos).
- `README.md` — "What's here" + commands bootstrap note reflect the split.
- `docs/superpowers/specs/2026-07-12-move-issue-workflow-commands-to-agent-pipeline-design.md` — record the §4 mechanics resolution.

**Removed from `config`:**
- `claude/commands/{issues,prs,parked,triage,done,new,enrich,enrich-phased,route,work,capture-idea}.md`
- `claude/commands/gh/` (entire dir), `claude/commands/fj/` (entire dir).

---

## Task 1: agent-pipeline — create `commands/` and copy the 34 console commands

**Files:**
- Create: `agent-pipeline/commands/{issues,prs,parked,triage,done,new,enrich,enrich-phased,route,work,capture-idea}.md`
- Create: `agent-pipeline/commands/gh/*.md` (13), `agent-pipeline/commands/fj/*.md` (10)

**Interfaces:**
- Consumes: the current `config/claude/commands/` working tree (source of truth for the byte-identical copies).
- Produces: `agent-pipeline/commands/` — the directory Task 2's linker walks and Task 4's config linker delegates to. Command bodies are unchanged; `/gh:enrich`, `/route`, etc. keep their names via the preserved subdir layout.

- [ ] **Step 1: Copy the moved files into a new `commands/` tree, preserving subdirs**

```bash
CFG="$HOME/repos/github/freaxnx01/public/config/claude/commands"
AP="$HOME/repos/github/freaxnx01/public/agent-pipeline"
mkdir -p "$AP/commands/gh" "$AP/commands/fj"

# Top-level routers (11)
for c in issues prs parked triage done new enrich enrich-phased route work capture-idea; do
  cp "$CFG/$c.md" "$AP/commands/$c.md"
done
# gh/ (all 13) and fj/ (all 10) — copy whole dirs, then drop their READMEs if any
cp "$CFG/gh/"*.md "$AP/commands/gh/"
cp "$CFG/fj/"*.md "$AP/commands/fj/"
```

- [ ] **Step 2: Verify the copy is complete and byte-identical**

Run:
```bash
AP="$HOME/repos/github/freaxnx01/public/agent-pipeline"
CFG="$HOME/repos/github/freaxnx01/public/config/claude/commands"
echo "count (want 34):"; find "$AP/commands" -name '*.md' ! -name 'README.md' | wc -l
echo "diffs (want none):"
for f in $(cd "$AP/commands" && find . -name '*.md' ! -name 'README.md'); do
  diff -q "$AP/commands/$f" "$CFG/$f" || echo "MISMATCH $f"
done
```
Expected: `count (want 34): 34`, and the diff loop prints nothing (no `MISMATCH`, no `differ`).

- [ ] **Step 3: Commit in agent-pipeline**

```bash
cd "$HOME/repos/github/freaxnx01/public/agent-pipeline"
git add commands
git commit -m "feat(commands): adopt issue-workflow operator console from config

Copies the 34 user-level console commands (forge routers + gh:/fj: families)
out of freaxnx01/config into this repo's new top-level commands/ dir. Bodies
are unchanged; full per-file history remains reachable in config's git log."
```

---

## Task 2: agent-pipeline — add `setup/link-commands.sh` and `commands/README.md`

**Files:**
- Create: `agent-pipeline/setup/link-commands.sh`
- Create: `agent-pipeline/commands/README.md`

**Interfaces:**
- Consumes: `agent-pipeline/commands/*.md` from Task 1.
- Produces: `setup/link-commands.sh`, invoked as `link-commands.sh [--copy] [--no-sync]`. It clones/pulls agent-pipeline (unless `--no-sync`), then symlinks (or copies) every `commands/**.md` except READMEs into `~/.claude/commands/`. Task 4's config linker calls this exact path with a forwarded mode/sync flag.

- [ ] **Step 1: Write the linker script**

Create `agent-pipeline/setup/link-commands.sh`:
```bash
#!/usr/bin/env bash
# setup/link-commands.sh
#
# Link (or copy) agent-pipeline's USER-LEVEL operator-console slash commands into
# ~/.claude/commands/ so they work from ANY repo. These are DISTINCT from this
# repo's PROJECT-SCOPED .claude/commands/ (commit, push, ui-*), which are active
# only inside agent-pipeline itself.
#
# Default is symlink (a `git pull` here then updates every machine instantly);
# pass --copy where symlinks are awkward (native Windows). Pass --no-sync to skip
# the clone/pull and just (re)link from the current working tree — used by tests
# and by config's linker once it has already synced.
#
# Idempotent: re-running refreshes the links/copies. Safe to run on every machine.
#
# Usage (existing machine, repo already cloned):
#   ~/repos/github/freaxnx01/public/agent-pipeline/setup/link-commands.sh [--copy] [--no-sync]
#
# Usage (new machine, nothing cloned yet — single-line bootstrap):
#   curl -fsSL https://raw.githubusercontent.com/freaxnx01/agent-pipeline/main/setup/link-commands.sh | bash

set -euo pipefail

REPO_URL="https://github.com/freaxnx01/agent-pipeline.git"
REPO_DIR="$HOME/repos/github/freaxnx01/public/agent-pipeline"
SRC_DIR="$REPO_DIR/commands"
DEST_DIR="$HOME/.claude/commands"

mode="link"
sync=1
for arg in "$@"; do
  case "$arg" in
    --copy)    mode="copy" ;;
    --no-sync) sync=0 ;;
  esac
done

# 1) Clone or fast-forward the agent-pipeline repo at the canonical path (unless --no-sync).
if [ "$sync" = 1 ]; then
  if [ ! -d "$REPO_DIR/.git" ]; then
    echo "→ cloning agent-pipeline repo to $REPO_DIR"
    mkdir -p "$(dirname "$REPO_DIR")"
    git clone "$REPO_URL" "$REPO_DIR"
  else
    echo "→ pulling latest at $REPO_DIR"
    git -C "$REPO_DIR" pull --ff-only
  fi
fi

# 2) Make sure ~/.claude/commands/ exists.
mkdir -p "$DEST_DIR"

# 3) Install each command .md, preserving subdirs (which become /namespace:cmd).
#    Skip any README.md at the top level or inside namespace dirs.
echo "→ installing agent-pipeline console commands into $DEST_DIR ($mode)"
while IFS= read -r f; do
  rel="${f#"$SRC_DIR"/}"
  case "$rel" in README.md|*/README.md) continue ;; esac
  dest="$DEST_DIR/$rel"
  mkdir -p "$(dirname "$dest")"
  if [ "$mode" = "copy" ]; then
    cp -f "$f" "$dest"
    echo "  copied  $rel"
  else
    ln -sfn "$f" "$dest"
    echo "  linked  $rel"
  fi
done < <(find "$SRC_DIR" -type f -name '*.md')

echo "✓ done — agent-pipeline console commands installed (e.g. /gh:enrich, /route, /capture-idea)"
```

- [ ] **Step 2: Make it executable and write the console index README**

```bash
chmod +x "$HOME/repos/github/freaxnx01/public/agent-pipeline/setup/link-commands.sh"
```

Create `agent-pipeline/commands/README.md`:
```markdown
# agent-pipeline operator console — user-level slash commands

These are **user-level** Claude Code slash commands: symlinked into
`~/.claude/commands/` by [`../setup/link-commands.sh`](../setup/link-commands.sh),
so they work from **any** repo. They are the human-facing front-end of this
pipeline — the issue→PR workflow you drive it with — and are **forge-agnostic**:
GitHub Actions today (`gh:*`), Forgejo Actions later (`fj:*`).

> **Not to be confused with** this repo's project-scoped
> [`.claude/commands/`](../.claude/commands/) (`commit`, `push`, `ui-*`), which
> are active only inside agent-pipeline. `commands/` here is user-level and global;
> `.claude/commands/` is project-local. See `docs/DECISIONS.md` (ADR-005).

## Install

`config`'s one-URL bootstrap installs these automatically (it clones this repo and
calls `setup/link-commands.sh`). To install just the console directly:

```bash
curl -fsSL https://raw.githubusercontent.com/freaxnx01/agent-pipeline/main/setup/link-commands.sh | bash
```

Pass `--copy` on filesystems without symlinks; `--no-sync` to relink from the
current working tree without pulling.

## Commands

**Forge routers** (auto-detect GitHub vs Forgejo from the `origin` remote, then
delegate to the matching `gh:`/`fj:` command):
`/issues` · `/prs` · `/parked` · `/triage` · `/done` · `/new` · `/enrich` ·
`/enrich-phased` · `/route` · `/work`

**Idea capture** (forge-agnostic, local — precedes the issue funnel):
`/capture-idea <idea>` — jot an idea into the current repo's `docs/ideas.md`.

**GitHub** (`gh/`): `/gh:new` · `/gh:issues` · `/gh:parked` · `/gh:triage` ·
`/gh:enrich` · `/gh:enrich-phased` · `/gh:route` · `/gh:work` · `/gh:assign` ·
`/gh:implement` · `/gh:prs` · `/gh:review` · `/gh:done`

**Forgejo** (`fj/`): `/fj:new` · `/fj:issues` · `/fj:parked` · `/fj:triage` ·
`/fj:enrich` · `/fj:enrich-phased` · `/fj:route` · `/fj:work` · `/fj:prs` · `/fj:done`

Each `.md` file's `description:` front-matter shows in the `/` autocomplete menu.
```

- [ ] **Step 3: Verify the linker installs all 34 with no dangling links (sandbox, `--no-sync`)**

Run the harness (from Global Constraints) against agent-pipeline's linker:
```bash
# harness invocation
SB="$(mktemp -d)"
mkdir -p "$SB/repos/github/freaxnx01/public"
ln -s "$HOME/repos/github/freaxnx01/public/config"         "$SB/repos/github/freaxnx01/public/config"
ln -s "$HOME/repos/github/freaxnx01/public/agent-pipeline" "$SB/repos/github/freaxnx01/public/agent-pipeline"
HOME="$SB" bash "$SB/repos/github/freaxnx01/public/agent-pipeline/setup/link-commands.sh" --no-sync
echo "count (want 34):"; find "$SB/.claude/commands" \( -type f -o -type l \) -name '*.md' | wc -l
echo "broken (want empty):"; find "$SB/.claude/commands" -type l ! -exec test -e {} \; -print
echo "gh/enrich ->"; readlink -f "$SB/.claude/commands/gh/enrich.md"
rm -rf "$SB"
```
Expected: `count (want 34): 34`; broken list empty; `gh/enrich ->` resolves to `…/agent-pipeline/commands/gh/enrich.md`.

- [ ] **Step 4: Commit in agent-pipeline**

```bash
cd "$HOME/repos/github/freaxnx01/public/agent-pipeline"
git add setup/link-commands.sh commands/README.md
git commit -m "feat(setup): add user-level console linker (link-commands.sh)

Thin linker mirroring config's pattern: symlinks commands/**.md into
~/.claude/commands/ (--copy / --no-sync supported). config's bootstrap calls
this so the source repo owns knowledge of its own layout."
```

---

## Task 3: agent-pipeline — widen the boundary in DESIGN.md and add ADR-005

**Files:**
- Modify: `agent-pipeline/docs/DESIGN.md` (line 31 boundary comment + the Scope section)
- Modify: `agent-pipeline/docs/DECISIONS.md` (append ADR-005)

**Interfaces:**
- Consumes: nothing runtime — documentation only.
- Produces: the "CI + console, forge-agnostic" framing that makes the relocation coherent (spec §1) and the user-level-vs-project-scoped distinction future contributors need (spec blast-radius note).

- [ ] **Step 1: Widen the repo boundary comment in DESIGN.md**

In `agent-pipeline/docs/DESIGN.md`, replace the line (currently line 31):
```text
freaxnx01/agent-pipeline       # NEW — the CI side (workflows, scripts, fixtures, docs)
```
with:
```text
freaxnx01/agent-pipeline       # the pipeline end-to-end: CI side (workflows, scripts, fixtures, docs) + operator console (commands/)
```

- [ ] **Step 2: Add a Scope bullet reflecting the console**

In `agent-pipeline/docs/DESIGN.md`, under the `## Scope` section, add this bullet after the existing "Personal repos only" bullet:
```markdown
- **CI side *and* operator console.** This repo owns both the CI implementation
  (`.github/workflows`, `scripts`, fixtures) **and** the user-level slash-command
  console (`commands/`) you drive the pipeline with — forge-agnostic across GitHub
  Actions (now) and Forgejo Actions (later). See ADR-005.
```

- [ ] **Step 3: Append ADR-005 to DECISIONS.md**

Append to `agent-pipeline/docs/DECISIONS.md`:
```markdown

## ADR-005 — Operator console lives here; user-level vs project-scoped commands (2026-07-12)

### Context

The issue-workflow slash commands (forge routers, `gh:*`, `fj:*`, `enrich`,
`route`, `work`, `capture-idea`) previously lived in `freaxnx01/config`, a repo
scoped to "Claude Code configuration." In practice they are the human-facing
front-end of *this* pipeline — they feed and drive it — so their home was wrong.
`agent-pipeline` is also intended to become forge-agnostic (GitHub Actions now,
Forgejo Actions later), which makes the `fj:*` half native to this repo, not
foreign.

### Decision

1. **`agent-pipeline` = the pipeline end-to-end** — the CI side **plus** the
   operator console. The console lives in a **new top-level `commands/`** directory.
2. **Two command surfaces, deliberately distinct:**
   - `commands/` — **user-level**. Symlinked into `~/.claude/commands/` by
     `setup/link-commands.sh`; active from **any** repo. This is the console.
   - `.claude/commands/` — **project-scoped** (`commit`, `push`, `ui-*`); active
     only inside agent-pipeline. Unchanged.
   Do not conflate them. A command that should work everywhere goes in `commands/`;
   one that only makes sense inside this repo goes in `.claude/commands/`.
3. **`config` stays the single one-URL bootstrap.** Its `setup/01-claude-commands.sh`
   links the retained generic commands, then clones this repo (if absent) and calls
   `setup/link-commands.sh`. This repo exposes the link step but does **not** grow a
   competing machine bootstrap.
4. Files were **copied** here and `git rm`'d from config (per-file history remains
   in config's log); no cross-repo history graft.

### Consequences

- `agent-pipeline` now has a user-level surface it didn't before — documented in
  `commands/README.md` and here so contributors don't confuse the two dirs.
- The "one curl sets up a machine" promise survives, now spanning two repos; config's
  bootstrap clones this repo idempotently and surfaces (not swallows) clone failure.
- Building the Forgejo Actions CI side later has a natural home; the `fj:*` console
  is already here waiting.
```

- [ ] **Step 4: Verify docs are coherent and commit**

Run:
```bash
cd "$HOME/repos/github/freaxnx01/public/agent-pipeline"
grep -n "operator console (commands/)" docs/DESIGN.md
grep -n "ADR-005" docs/DECISIONS.md
```
Expected: both greps return exactly one match.

```bash
git add docs/DESIGN.md docs/DECISIONS.md
git commit -m "docs: reframe agent-pipeline as CI + operator console (ADR-005)

Widens the repo boundary (DESIGN.md) and records the user-level commands/ vs
project-scoped .claude/commands/ distinction and the console relocation (ADR-005)."
```

> **agent-pipeline side complete.** Do not push yet — the coordinated push happens in Task 7 (agent-pipeline first, then config).

---

## Task 4: config — rewire `setup/01-claude-commands.sh` to also link the console

**Files:**
- Modify: `config/setup/01-claude-commands.sh`

**Interfaces:**
- Consumes: `agent-pipeline/setup/link-commands.sh` (Task 2) at `$HOME/repos/github/freaxnx01/public/agent-pipeline/setup/link-commands.sh`.
- Produces: a config linker that (a) parses `--copy`/`--no-sync`, (b) links the retained generic config commands, (c) clones agent-pipeline if absent (unless `--no-sync`), (d) invokes agent-pipeline's linker forwarding the mode/sync flags. Consumed by `bootstrap.sh` (unchanged — it already passes `"$@"`) and by `/update-commands` (Task 6).

- [ ] **Step 1: Replace the arg parsing + config clone/pull to honor `--no-sync`**

In `config/setup/01-claude-commands.sh`, replace:
```bash
mode="link"
[ "${1:-}" = "--copy" ] && mode="copy"

# 1) Clone or fast-forward the config repo at the canonical path.
if [ ! -d "$REPO_DIR/.git" ]; then
  echo "→ cloning config repo to $REPO_DIR"
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone "$REPO_URL" "$REPO_DIR"
else
  echo "→ pulling latest at $REPO_DIR"
  git -C "$REPO_DIR" pull --ff-only
fi
```
with:
```bash
mode="link"
sync=1
for arg in "$@"; do
  case "$arg" in
    --copy)    mode="copy" ;;
    --no-sync) sync=0 ;;
  esac
done

# 1) Clone or fast-forward the config repo at the canonical path (unless --no-sync).
if [ "$sync" = 1 ]; then
  if [ ! -d "$REPO_DIR/.git" ]; then
    echo "→ cloning config repo to $REPO_DIR"
    mkdir -p "$(dirname "$REPO_DIR")"
    git clone "$REPO_URL" "$REPO_DIR"
  else
    echo "→ pulling latest at $REPO_DIR"
    git -C "$REPO_DIR" pull --ff-only
  fi
fi
```

- [ ] **Step 2: After the config link loop, delegate the console to agent-pipeline**

In `config/setup/01-claude-commands.sh`, replace the final line:
```bash
echo "✓ done — type / in any project to see the commands (e.g. /loose-ends, /clear-check)"
```
with:
```bash
# 4) Install the agent-pipeline operator-console commands (issue-workflow routers
#    + gh:/fj: families). They live in a SEPARATE repo now; config stays the single
#    orchestrator by cloning it if absent and calling its own link step, so the
#    "one curl sets up a machine" promise survives.
AP_REPO_URL="https://github.com/freaxnx01/agent-pipeline.git"
AP_REPO_DIR="$HOME/repos/github/freaxnx01/public/agent-pipeline"
AP_LINK="$AP_REPO_DIR/setup/link-commands.sh"

if [ "$sync" = 1 ] && [ ! -d "$AP_REPO_DIR/.git" ]; then
  echo "→ cloning agent-pipeline repo to $AP_REPO_DIR (for console commands)"
  mkdir -p "$(dirname "$AP_REPO_DIR")"
  git clone "$AP_REPO_URL" "$AP_REPO_DIR"
fi

if [ -f "$AP_LINK" ]; then
  ap_args=()
  [ "$mode" = "copy" ] && ap_args+=(--copy)
  [ "$sync" = 0 ] && ap_args+=(--no-sync)
  echo "→ linking agent-pipeline console commands via $AP_LINK"
  bash "$AP_LINK" ${ap_args[@]+"${ap_args[@]}"}
else
  echo "⚠ agent-pipeline link step not found at $AP_LINK — console commands (gh:/fj:/routers) NOT installed." >&2
  echo "  Clone https://github.com/freaxnx01/agent-pipeline and re-run, or run with sync enabled." >&2
fi

echo "✓ done — type / in any project to see the commands (generic from config, console from agent-pipeline)"
```

- [ ] **Step 3: Syntax-check the script**

Run:
```bash
bash -n "$HOME/repos/github/freaxnx01/public/config/setup/01-claude-commands.sh" && echo "syntax OK"
```
Expected: `syntax OK`.

- [ ] **Step 4: Verify config's linker installs BOTH sets with no dangling links (sandbox, `--no-sync`)**

> Note: agent-pipeline still has its files (Task 1) and linker (Task 2), and config still has all its originals (git rm is Task 5). Because the agent-pipeline linker runs **last**, the 34 moved names already resolve into agent-pipeline here.

Run:
```bash
SB="$(mktemp -d)"
mkdir -p "$SB/repos/github/freaxnx01/public"
ln -s "$HOME/repos/github/freaxnx01/public/config"         "$SB/repos/github/freaxnx01/public/config"
ln -s "$HOME/repos/github/freaxnx01/public/agent-pipeline" "$SB/repos/github/freaxnx01/public/agent-pipeline"
HOME="$SB" bash "$SB/repos/github/freaxnx01/public/config/setup/01-claude-commands.sh" --no-sync
echo "broken (want empty):"; find "$SB/.claude/commands" -type l ! -exec test -e {} \; -print
echo "console from agent-pipeline:"
readlink -f "$SB/.claude/commands/gh/enrich.md"; readlink -f "$SB/.claude/commands/route.md"
echo "generic from config:"
readlink -f "$SB/.claude/commands/handoff.md"; readlink -f "$SB/.claude/commands/wt/status.md"
rm -rf "$SB"
```
Expected: broken list empty; `gh/enrich.md` and `route.md` resolve into `…/agent-pipeline/commands/…`; `handoff.md` and `wt/status.md` resolve into `…/config/claude/commands/…`.

- [ ] **Step 5: Commit in config**

```bash
cd "$HOME/repos/github/freaxnx01/public/config"
git add setup/01-claude-commands.sh
git commit -m "feat(setup): link agent-pipeline console after generic commands

01-claude-commands.sh now links the retained generic commands, then clones
agent-pipeline (if absent) and invokes its link-commands.sh for the console.
Adds --no-sync to relink without pulling. config stays the one-URL bootstrap."
```

---

## Task 5: config — remove the 34 moved command files

**Files:**
- Remove: 11 top-level routers + `claude/commands/gh/` + `claude/commands/fj/` from config.

**Interfaces:**
- Consumes: nothing.
- Produces: a `config/claude/commands/` that contains only the retained 11 + README. After this task the console resolves solely from agent-pipeline.

- [ ] **Step 1: `git rm` the moved files**

```bash
cd "$HOME/repos/github/freaxnx01/public/config"
git rm claude/commands/issues.md claude/commands/prs.md claude/commands/parked.md \
       claude/commands/triage.md claude/commands/done.md claude/commands/new.md \
       claude/commands/enrich.md claude/commands/enrich-phased.md claude/commands/route.md \
       claude/commands/work.md claude/commands/capture-idea.md
git rm -r claude/commands/gh claude/commands/fj
```

- [ ] **Step 2: Verify only the retained set remains**

Run:
```bash
cd "$HOME/repos/github/freaxnx01/public/config"
echo "remaining top-level .md (want 10: 9 commands + README):"
find claude/commands -maxdepth 1 -name '*.md' | sort
echo "remaining subdirs (want only wt):"
find claude/commands -mindepth 1 -maxdepth 1 -type d
```
Expected: the top-level list is exactly `README.md`, `clear-check.md`, `commands.md`, `handoff.md`, `loose-ends.md`, `pickup.md`, `subagent-driven.md`, `todo.md`, `update-commands.md`, `wrap-up.md` (10 files); the only subdir is `claude/commands/wt`.

- [ ] **Step 3: Verify config's linker now installs the console solely from agent-pipeline, still no dangling links (sandbox, `--no-sync`)**

Run:
```bash
SB="$(mktemp -d)"
mkdir -p "$SB/repos/github/freaxnx01/public"
ln -s "$HOME/repos/github/freaxnx01/public/config"         "$SB/repos/github/freaxnx01/public/config"
ln -s "$HOME/repos/github/freaxnx01/public/agent-pipeline" "$SB/repos/github/freaxnx01/public/agent-pipeline"
HOME="$SB" bash "$SB/repos/github/freaxnx01/public/config/setup/01-claude-commands.sh" --no-sync
echo "total (want 45):"; find "$SB/.claude/commands" \( -type f -o -type l \) -name '*.md' | wc -l
echo "broken (want empty):"; find "$SB/.claude/commands" -type l ! -exec test -e {} \; -print
echo "moved command resolves to agent-pipeline:"; readlink -f "$SB/.claude/commands/capture-idea.md"
rm -rf "$SB"
```
Expected: `total (want 45): 45` (11 config retained + 34 console); broken list empty; `capture-idea.md` resolves into `…/agent-pipeline/commands/capture-idea.md`.

- [ ] **Step 4: Commit in config**

```bash
cd "$HOME/repos/github/freaxnx01/public/config"
git commit -m "refactor(commands): remove issue-workflow console (moved to agent-pipeline)

Removes the 34 forge routers + gh:/fj: commands now owned by agent-pipeline.
config's linker installs them from there. Per-file history remains in this log."
```

---

## Task 6: config — update the READMEs and `/update-commands`

**Files:**
- Modify: `config/claude/commands/README.md` (trim to retained set; point at agent-pipeline)
- Modify: `config/README.md` ("What's here" + commands note)
- Modify: `config/claude/commands/update-commands.md` (two sources)

**Interfaces:**
- Consumes: the Task-5 state (config holds only retained commands) and the Task-2/4 install mechanics.
- Produces: docs that match reality — success criteria #3 and #5.

- [ ] **Step 1: Rewrite `config/claude/commands/README.md` to the retained set**

Replace the entire file with:
```markdown
# Claude Code shared slash commands

User-level [custom slash commands](https://docs.anthropic.com/en/docs/claude-code/slash-commands#custom-slash-commands)
for Claude Code. Each `.md` file becomes a `/<filename>` command (subdirs become
`/namespace:command`); the `description:` front-matter shows in the `/`
autocomplete menu.

> **Where the issue-workflow console went.** The forge routers (`/issues`,
> `/enrich`, `/route`, `/work`, …) and the `gh:*` / `fj:*` families now live in
> **[freaxnx01/agent-pipeline](https://github.com/freaxnx01/agent-pipeline)** under
> its top-level `commands/` — they are the pipeline's operator console. config's
> bootstrap still installs them (it clones agent-pipeline and calls its link step),
> so `/commands` lists everything regardless of origin. This README covers only the
> generic Claude Code commands that remain in config.

## At a glance

**Meta**
- `/commands` — list my custom slash commands (user + project), grouped
- `/update-commands` — update user-level commands from **both** sources (config + agent-pipeline): pull + relink

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
| [`/update-commands`](update-commands.md) | Updates user-level commands from **both** config and agent-pipeline — pulls latest `main` and re-symlinks into `~/.claude/commands/`. Read-only; no auth. |
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
into `~/.claude/commands/`, **and** clones agent-pipeline to install the console
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
Copy-Item -Force "$HOME\repos\...\config\claude\commands\*.md" "$HOME\.claude\commands\"
Copy-Item -Recurse -Force "$HOME\repos\...\agent-pipeline\commands\*" "$HOME\.claude\commands\"
```

## Verify

Start a **new** session (or it may already be picked up) and type `/` — commands
should appear in the menu. Run `/clear-check` to confirm it responds.

## Adding a command

A generic Claude Code command goes here; an issue-workflow / pipeline command goes in
`agent-pipeline/commands/`. Drop a new `<name>.md` with a `description:` front-matter,
commit, and re-run the matching linker on each machine.
```

- [ ] **Step 2: Update `config/README.md` "What's here" and the commands bootstrap note**

In `config/README.md`, in the bootstrap table row for Commands, replace:
```markdown
| Commands | [`setup/01-claude-commands.sh`](setup/01-claude-commands.sh) | Slash commands into `~/.claude/commands/` (symlinked) — see [list](claude/commands/README.md) |
```
with:
```markdown
| Commands | [`setup/01-claude-commands.sh`](setup/01-claude-commands.sh) | Generic slash commands from this repo **plus** the issue-workflow console from [agent-pipeline](https://github.com/freaxnx01/agent-pipeline) (cloned + linked automatically) into `~/.claude/commands/` — see [list](claude/commands/README.md) |
```

And in the `## What's here` section, replace:
```markdown
- [`claude/`](claude/) — partials, [commands](claude/commands/README.md), and [hooks](claude/hooks/)
```
with:
```markdown
- [`claude/`](claude/) — partials, generic [commands](claude/commands/README.md), and [hooks](claude/hooks/)
  (the issue-workflow console commands live in [agent-pipeline](https://github.com/freaxnx01/agent-pipeline)`/commands/`, installed by the same bootstrap)
```

- [ ] **Step 3: Update `config/claude/commands/update-commands.md` to two sources**

Replace the body of `config/claude/commands/update-commands.md` (keep the front-matter) so it pulls + relinks both repos. Replace the file with:
```markdown
---
description: Update my user-level slash commands from the config repo (pull + relink)
---

Update my personal user-level Claude Code slash commands. They now come from **two**
source repos, both installed into `~/.claude/commands/`:

- **[freaxnx01/config](https://github.com/freaxnx01/config)** (`~/repos/github/freaxnx01/public/config`)
  — the generic commands (session hygiene, handoff/pickup, `wt:*`, meta).
- **[freaxnx01/agent-pipeline](https://github.com/freaxnx01/agent-pipeline)** (`~/repos/github/freaxnx01/public/agent-pipeline`)
  — the issue-workflow operator console (forge routers, `gh:*`, `fj:*`, `capture-idea`).

Steps:

1. Run the idempotent config installer. It pulls the latest `main` for config,
   re-symlinks the generic commands, **then** clones/pulls agent-pipeline and
   re-symlinks the console commands via its own link step — so one command refreshes
   both sources:

   ```bash
   bash ~/repos/github/freaxnx01/public/config/setup/01-claude-commands.sh
   ```

2. Report concisely which commands were added, changed, or removed since before the
   pull. Use the installer output plus, for whichever repos fast-forwarded:

   ```bash
   git -C ~/repos/github/freaxnx01/public/config         log --oneline @{1}.. 2>/dev/null
   git -C ~/repos/github/freaxnx01/public/agent-pipeline log --oneline @{1}.. 2>/dev/null
   ```

   If nothing changed in either, just say "Already up to date."

Notes:

- This is read-only (pull + relink) — no auth needed.
- Do **not** confuse this with `/sync-ai-instructions`, which refreshes a *project's*
  `.ai/` + `.claude/commands/` + `CLAUDE.md` from the `freaxnx01/ai-instructions`
  repo. This command is only about the user-level commands shared across all projects.
```

- [ ] **Step 4: Verify no stale references to moved commands remain in config docs**

Run:
```bash
cd "$HOME/repos/github/freaxnx01/public/config"
echo "== broken relative links to moved files in commands/README.md (want none) =="
grep -nE '\]\((gh|fj)/|\]\((issues|prs|parked|triage|done|new|enrich|enrich-phased|route|work|capture-idea)\.md\)' claude/commands/README.md || echo "  none"
```
Expected: `none` — the rewritten README no longer links to any moved file.

- [ ] **Step 5: Commit in config**

```bash
cd "$HOME/repos/github/freaxnx01/public/config"
git add claude/commands/README.md README.md claude/commands/update-commands.md
git commit -m "docs(commands): retarget READMEs + update-commands after console move

commands/README.md now covers only the retained generic set and points at
agent-pipeline for the console; root README reflects the two-source install;
/update-commands pulls + relinks both repos."
```

---

## Task 7: config — record spec resolution + final end-to-end verification

**Files:**
- Modify: `config/docs/superpowers/specs/2026-07-12-move-issue-workflow-commands-to-agent-pipeline-design.md` (§4 mechanics note)

**Interfaces:**
- Consumes: the completed state of Tasks 1–6.
- Produces: a spec that records how §4 was executed, and a green end-to-end verification against all five success criteria.

- [ ] **Step 1: Record the §4 mechanics resolution in the spec**

In `config/docs/superpowers/specs/2026-07-12-move-issue-workflow-commands-to-agent-pipeline-design.md`, under `### 4. Docs & cutover`, replace the first bullet:
```markdown
- `git mv` the command files with history preserved.
```
with:
```markdown
- **Copy** the command files into `agent-pipeline/commands/` and `git rm` them from
  `config` (resolved 2026-07-12 — pragmatic copy over a cross-repo history graft).
  Per-file history stays reachable in config's git log; agent-pipeline starts them
  fresh with a provenance note in the commit message.
```

- [ ] **Step 2: Full end-to-end verification against the success criteria**

Run the sandbox bootstrap simulation (config linker drives both repos, `--no-sync`):
```bash
SB="$(mktemp -d)"
mkdir -p "$SB/repos/github/freaxnx01/public"
ln -s "$HOME/repos/github/freaxnx01/public/config"         "$SB/repos/github/freaxnx01/public/config"
ln -s "$HOME/repos/github/freaxnx01/public/agent-pipeline" "$SB/repos/github/freaxnx01/public/agent-pipeline"
HOME="$SB" bash "$SB/repos/github/freaxnx01/public/config/setup/01-claude-commands.sh" --no-sync

echo "== SC1/SC2: all 45 commands present, none dangling =="
echo "total (want 45):"; find "$SB/.claude/commands" \( -type f -o -type l \) -name '*.md' | wc -l
echo "broken (want empty):"; find "$SB/.claude/commands" -type l ! -exec test -e {} \; -print

echo "== SC2: key commands resolve from the right repo =="
for c in gh/enrich.md fj/enrich.md route.md work.md capture-idea.md; do
  printf '  %-16s -> %s\n' "$c" "$(readlink -f "$SB/.claude/commands/$c")"   # want agent-pipeline
done
for c in handoff.md wt/status.md subagent-driven.md; do
  printf '  %-16s -> %s\n' "$c" "$(readlink -f "$SB/.claude/commands/$c")"   # want config
done

echo "== SC3: config holds only the retained generic set =="
find "$SB/repos/github/freaxnx01/public/config/claude/commands" -name '*.md' ! -name 'README.md' | sed "s#$SB/repos/github/freaxnx01/public/config/claude/commands/##" | sort

echo "== SC4: agent-pipeline owns the console (34) =="
find "$SB/repos/github/freaxnx01/public/agent-pipeline/commands" -name '*.md' ! -name 'README.md' | wc -l
rm -rf "$SB"
```
Expected:
- total `45`; broken list empty (SC1, SC2, SC5).
- `gh/enrich`, `fj/enrich`, `route`, `work`, `capture-idea` resolve into `…/agent-pipeline/commands/…` (SC2, SC4).
- `handoff`, `wt/status`, `subagent-driven` resolve into `…/config/claude/commands/…`.
- config's list is exactly the 11 retained (SC3).
- agent-pipeline console count is `34` (SC4).

- [ ] **Step 3: Verify `--copy` mode also works end-to-end (Windows path, config #31 not regressed)**

Run:
```bash
SB="$(mktemp -d)"
mkdir -p "$SB/repos/github/freaxnx01/public"
ln -s "$HOME/repos/github/freaxnx01/public/config"         "$SB/repos/github/freaxnx01/public/config"
ln -s "$HOME/repos/github/freaxnx01/public/agent-pipeline" "$SB/repos/github/freaxnx01/public/agent-pipeline"
HOME="$SB" bash "$SB/repos/github/freaxnx01/public/config/setup/01-claude-commands.sh" --copy --no-sync
echo "total real files (want 45, all regular files not links):"
find "$SB/.claude/commands" -type f -name '*.md' | wc -l
echo "symlinks in copy mode (want 0):"; find "$SB/.claude/commands" -type l | wc -l
rm -rf "$SB"
```
Expected: `45` regular files; `0` symlinks.

- [ ] **Step 4: Commit the spec update**

```bash
cd "$HOME/repos/github/freaxnx01/public/config"
git add docs/superpowers/specs/2026-07-12-move-issue-workflow-commands-to-agent-pipeline-design.md
git commit -m "docs(spec): record copy+git-rm cutover mechanics (§4)"
```

- [ ] **Step 5: Coordinated push (agent-pipeline first, then config)**

> This is the one hard-ordering step (Global Constraints). Push agent-pipeline first so its files + link step are live before config removes the console and points at it. Confirm branch names before pushing.

```bash
# agent-pipeline first
cd "$HOME/repos/github/freaxnx01/public/agent-pipeline"
git log --oneline -3        # confirm the 3 console commits are present
git push                    # push the console + linker + docs

# then config
cd "$HOME/repos/github/freaxnx01/public/config"
git log --oneline -6        # confirm linker/rm/docs/spec commits are present
git push                    # or open a PR if that's the flow
```

- [ ] **Step 6: (optional, live) real install on this machine**

Once both are pushed, run the real linker (no `--no-sync`) to update this machine's actual `~/.claude/commands/` and confirm in a fresh session:
```bash
bash "$HOME/repos/github/freaxnx01/public/config/setup/01-claude-commands.sh"
```
Then in a new Claude Code session, type `/` and confirm `/gh:enrich`, `/route`, `/capture-idea`, `/handoff`, `/wt:status` all appear.

---

## Success Criteria (from the spec) → covered by

1. **One `curl … | bash` still yields all commands** — Task 4 (linker rewire) + Task 7 Step 2 (total 45, none dangling).
2. **`/gh:enrich`, `/fj:enrich`, `/route`, `/work`, `/capture-idea` run identically from any repo** — Task 1 (verbatim copy) + Task 7 Step 2 (resolve into agent-pipeline).
3. **config/claude/commands/ has only the retained generic set; README reflects it** — Task 5 (git rm) + Task 6 (README rewrite) + Task 7 Step 2 (config list = 11).
4. **agent-pipeline owns the console; README/DESIGN updated to CI+console framing** — Tasks 1–3 + Task 7 Step 2 (console count 34).
5. **No dangling symlinks; `/update-commands` refreshes both sources** — every sandbox run asserts empty broken-link list; Task 6 Step 3 (update-commands two sources).
