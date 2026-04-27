# clrepo Pull/Sync on Startup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fast-forward pull the active branch in `_clrepo_launch` immediately after `cd`, with safe skip conditions and a `--no-sync` opt-out.

**Architecture:** Two new shell helpers (`_clrepo_warn`, `_clrepo_sync`) plus a small refactor that extracts the existing tmux session-name derivation into `_clrepo_tmux_session_name` so the new sync step's reattach-skip check uses the exact same name `_clrepo_launch` does. All changes live in one file.

**Tech Stack:** Bash, `git`, `coreutils` `timeout`. No new dependencies.

**Repo:** `freaxnx01/config` (the shell-config repo used across claude-dev LXC, WSL2 on Win11, and the company notebook).

**Spec:** `docs/superpowers/specs/2026-04-27-clrepo-pull-on-startup-design.md`

**Testing note:** The repo has no test harness. Verification is by running commands and inspecting output. Each task ends with a concrete verification step. The final task runs `bash-language-server` over the modified file.

---

## File Structure

**Modified files:**
- `shell/clrepo.sh` — all code changes here:
  - New helper `_clrepo_warn` near the top.
  - New helper `_clrepo_tmux_session_name` (extracted from `_clrepo_launch` inline derivation).
  - Refactor `_clrepo_launch` to use `_clrepo_tmux_session_name`.
  - New function `_clrepo_sync` placed immediately above `_clrepo_launch`.
  - `_clrepo_launch` body: call `_clrepo_sync` right after `cd`.
  - `clrepo()` arg parser: add `_CLREPO_NO_SYNC=0` local; add `--no-sync` case branch; add help-text line.
  - `_clrepo` completion: add `--no-sync` to flags list.

**New files:** None.

---

## Task 1: Add `_clrepo_warn` helper

**Why:** A single yellow-prefixed stderr printer is reused by every skip path in `_clrepo_sync`. Defining it once keeps the call sites readable and lets us tweak the format in one place.

**Files:**
- Modify: `shell/clrepo.sh` — insert below the `_CLREPO_OWNER` config block (after line 34, before `# Emit forge targets:` on line 36).

- [ ] **Step 1: Insert helper**

After the `_CLREPO_OWNER="$_CLREPO_CACHE/owner.json"` line and its blank line, add:

```bash
# Yellow-prefixed warning to stderr. Used by _clrepo_sync skip paths.
_clrepo_warn() {
  printf '\033[33mclrepo: %s\033[0m\n' "$*" >&2
}
```

- [ ] **Step 2: Verify it works**

Source the file and call the helper:

```bash
( source shell/clrepo.sh && _clrepo_warn "test message" ) 2>&1
```

Expected: yellow-coloured `clrepo: test message` printed to stderr.

- [ ] **Step 3: Commit**

```bash
git add shell/clrepo.sh
git commit -m "clrepo: add _clrepo_warn helper for yellow stderr warnings"
```

---

## Task 2: Extract `_clrepo_tmux_session_name` helper and refactor `_clrepo_launch`

**Why:** The new `_clrepo_sync` skip-on-reattach check must use the *same* tmux session name as `_clrepo_launch`. Inline derivation in two places is a drift hazard; extract once now.

**Files:**
- Modify: `shell/clrepo.sh` — add the helper just above `_clrepo_launch` (around line 740). Update the two inline derivations inside `_clrepo_launch` (currently around lines 759–760 and 779–781).

**Note:** The existing inline derivation appears in the `--no-channel` legacy branch (lines 759–760) and the slot-mode branch (lines 779–781). Both must be updated.

- [ ] **Step 1: Add the helper**

Immediately above the line `_clrepo_launch() {`, insert:

```bash
# Derive a stable tmux session name from repo basename + optional worktree.
# Identical for a given (repo, worktree) pair so reattach checks match
# session creates.
_clrepo_tmux_session_name() {
  local s="$1"
  [ -n "${2:-}" ] && s="$1-$2"
  printf '%s' "${s//[^A-Za-z0-9_-]/_}"
}
```

- [ ] **Step 2: Replace the legacy-branch inline derivation**

In the `--no-channel` legacy branch of `_clrepo_launch`, find this block (currently lines 758–763):

```bash
    if [ -n "${SSH_CONNECTION:-}" ] && command -v tmux >/dev/null; then
      local session="$repo"
      [ -n "$worktree" ] && session="$repo-$worktree"
      session="${session//[^A-Za-z0-9_-]/_}"
      tmux new-session -A -s "$session" claude "${claude_args[@]}"
    else
```

Replace with:

```bash
    if [ -n "${SSH_CONNECTION:-}" ] && command -v tmux >/dev/null; then
      local session
      session=$(_clrepo_tmux_session_name "$repo" "$worktree")
      tmux new-session -A -s "$session" claude "${claude_args[@]}"
    else
```

- [ ] **Step 3: Replace the slot-mode branch inline derivation**

In the slot-mode branch of `_clrepo_launch`, find this block (currently lines 778–781):

```bash
  if [ -n "${SSH_CONNECTION:-}" ] && command -v tmux >/dev/null; then
    local session="$repo"
    [ -n "$worktree" ] && session="$repo-$worktree"
    session="${session//[^A-Za-z0-9_-]/_}"
```

Replace with:

```bash
  if [ -n "${SSH_CONNECTION:-}" ] && command -v tmux >/dev/null; then
    local session
    session=$(_clrepo_tmux_session_name "$repo" "$worktree")
```

- [ ] **Step 4: Verify the helper produces the expected names**

```bash
( source shell/clrepo.sh
  _clrepo_tmux_session_name config; echo
  _clrepo_tmux_session_name config feature/foo; echo
  _clrepo_tmux_session_name "weird name!" ""; echo
)
```

Expected output (one per line):
```
config
config-feature_foo
weird_name_
```

- [ ] **Step 5: Verify `clrepo` still loads cleanly**

```bash
bash -n shell/clrepo.sh && echo OK
```

Expected: `OK`.

- [ ] **Step 6: Commit**

```bash
git add shell/clrepo.sh
git commit -m "clrepo: extract _clrepo_tmux_session_name helper"
```

---

## Task 3: Add `_clrepo_sync` function

**Why:** The core of the feature. Runs after `cd` to perform the safe fast-forward pull described in the spec.

**Files:**
- Modify: `shell/clrepo.sh` — insert immediately above `_clrepo_launch() {` (after the `_clrepo_tmux_session_name` helper added in Task 2).

- [ ] **Step 1: Insert `_clrepo_sync`**

Immediately above `_clrepo_launch() {`, after the `_clrepo_tmux_session_name` helper, insert:

```bash
# Fast-forward sync of the current branch with its upstream before launch.
# Args: $1 = repo basename, $2 = optional worktree name.
# Never fails the launch; every error path returns 0 after a stderr line.
_clrepo_sync() {
  local repo="$1" worktree="${2:-}"
  [ "${_CLREPO_NO_SYNC:-0}" = 1 ] && return 0

  # Skip if we're about to reattach an existing tmux session.
  if [ -n "${SSH_CONNECTION:-}" ] && command -v tmux >/dev/null; then
    local session
    session=$(_clrepo_tmux_session_name "$repo" "$worktree")
    tmux has-session -t "$session" 2>/dev/null && return 0
  fi

  local branch upstream
  branch=$(git symbolic-ref --quiet --short HEAD) || {
    _clrepo_warn "detached HEAD, skipping sync"; return 0; }
  upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) || {
    _clrepo_warn "no upstream for $branch, skipping sync"; return 0; }
  if ! git diff --quiet || ! git diff --cached --quiet; then
    _clrepo_warn "dirty working tree, skipping sync"; return 0
  fi

  timeout 10 git fetch --quiet 2>/dev/null || {
    _clrepo_warn "fetch failed or timed out, skipping sync"; return 0; }

  local local_sha upstream_sha base
  local_sha=$(git rev-parse HEAD)
  upstream_sha=$(git rev-parse '@{u}')
  [ "$local_sha" = "$upstream_sha" ] && return 0

  base=$(git merge-base HEAD '@{u}')
  if [ "$base" = "$upstream_sha" ]; then
    return 0  # local is ahead of upstream — fine, nothing to pull
  elif [ "$base" = "$local_sha" ]; then
    git merge --ff-only --quiet '@{u}' || {
      _clrepo_warn "ff-only merge failed unexpectedly, skipping sync"; return 0; }
    printf 'clrepo: pulled %s..%s on %s\n' \
      "$(git rev-parse --short "$local_sha")" \
      "$(git rev-parse --short "$upstream_sha")" "$branch" >&2
  else
    _clrepo_warn "$branch diverged from $upstream, skipping sync"
  fi
}
```

- [ ] **Step 2: Syntax-check the file**

```bash
bash -n shell/clrepo.sh && echo OK
```

Expected: `OK`.

- [ ] **Step 3: Smoke-test the function in this very repo (clean tree, up-to-date)**

```bash
( source shell/clrepo.sh
  cd /home/freax/projects/repos/github/freaxnx01/public/config
  _clrepo_sync config
)
```

Expected: silent (no output) if local matches origin/main. (If local is behind, you'll see a `clrepo: pulled …` line; if dirty, a yellow warning. Any of these is acceptable evidence the function ran.)

- [ ] **Step 4: Smoke-test detached HEAD**

```bash
( source shell/clrepo.sh
  cd /tmp
  rm -rf clrepo-sync-test && git clone --quiet \
    /home/freax/projects/repos/github/freaxnx01/public/config clrepo-sync-test
  cd clrepo-sync-test
  git checkout --quiet HEAD~1 2>/dev/null || git checkout --quiet HEAD
  _clrepo_sync clrepo-sync-test
)
```

Expected: yellow `clrepo: detached HEAD, skipping sync`.

- [ ] **Step 5: Smoke-test no-upstream**

```bash
( source shell/clrepo.sh
  cd /tmp/clrepo-sync-test
  git checkout --quiet -b throwaway
  _clrepo_sync clrepo-sync-test
)
```

Expected: yellow `clrepo: no upstream for throwaway, skipping sync`.

- [ ] **Step 6: Smoke-test dirty tree**

```bash
( source shell/clrepo.sh
  cd /tmp/clrepo-sync-test
  git checkout --quiet main 2>/dev/null || git checkout --quiet master
  echo dirty >> README.md 2>/dev/null || echo dirty > dirty.txt
  git add -N dirty.txt 2>/dev/null || true
  echo dirty2 >> README.md
  _clrepo_sync clrepo-sync-test
)
```

Expected: yellow `clrepo: dirty working tree, skipping sync`.

- [ ] **Step 7: Smoke-test --no-sync env override**

```bash
( source shell/clrepo.sh
  cd /tmp/clrepo-sync-test
  git checkout --quiet main 2>/dev/null || git checkout --quiet master
  git stash --quiet 2>/dev/null || true
  _CLREPO_NO_SYNC=1 _clrepo_sync clrepo-sync-test
)
```

Expected: silent, no fetch.

- [ ] **Step 8: Cleanup**

```bash
rm -rf /tmp/clrepo-sync-test
```

- [ ] **Step 9: Commit**

```bash
git add shell/clrepo.sh
git commit -m "clrepo: add _clrepo_sync for safe ff-pull on launch"
```

---

## Task 4: Wire `--no-sync` flag in `clrepo()`

**Why:** Surface the opt-out so users can skip sync on a per-invocation basis.

**Files:**
- Modify: `shell/clrepo.sh` — `clrepo()` arg-parser block (currently around lines 813–857).

- [ ] **Step 1: Add `_CLREPO_NO_SYNC=0` to the locals line**

Find this line (currently line 814):

```bash
  local with_remote=0 force_refresh=0 mode_delete=0 worktree="" _CLREPO_NO_CHANNEL=0 _CLREPO_FORCED_SLOT=""
```

Replace with:

```bash
  local with_remote=0 force_refresh=0 mode_delete=0 worktree="" _CLREPO_NO_CHANNEL=0 _CLREPO_FORCED_SLOT="" _CLREPO_NO_SYNC=0
```

- [ ] **Step 2: Add the case branch**

Find the `--no-channel` case branch (currently line 820):

```bash
      --no-channel)   _CLREPO_NO_CHANNEL=1; shift ;;
```

Insert immediately after it:

```bash
      --no-sync)      _CLREPO_NO_SYNC=1; shift ;;
```

- [ ] **Step 3: Add help-text line**

In the heredoc inside the `-h|--help` case branch, find the line:

```bash
  --no-channel            legacy mode, no slot allocation, no Telegram
```

Insert immediately after it:

```bash
  --no-sync               skip the upstream fast-forward pull on startup
```

- [ ] **Step 4: Verify help text**

```bash
( source shell/clrepo.sh && clrepo --help )
```

Expected: help output now contains the `--no-sync` line.

- [ ] **Step 5: Verify flag parses without error**

```bash
( source shell/clrepo.sh && clrepo --no-sync --help )
```

Expected: same help output, no error.

- [ ] **Step 6: Commit**

```bash
git add shell/clrepo.sh
git commit -m "clrepo: add --no-sync flag (parser + help)"
```

---

## Task 5: Call `_clrepo_sync` from `_clrepo_launch`

**Why:** Wire the new function into the launch path so it actually runs.

**Files:**
- Modify: `shell/clrepo.sh` — `_clrepo_launch` body (currently around line 744).

- [ ] **Step 1: Insert the call**

Find this block at the top of `_clrepo_launch` (currently lines 740–747):

```bash
_clrepo_launch() {
  local sel="$1"
  local worktree="${2:-}"
  local mru="$_CLREPO_CACHE/mru"
  cd "$_CLREPO_BASE/$sel" || return
  { printf '%s
' "$sel"; grep -vxF "$sel" "$mru" 2>/dev/null; } | head -10 > "$mru.tmp" && mv "$mru.tmp" "$mru"
```

Insert a `_clrepo_sync` call between the `cd` and the MRU update:

```bash
_clrepo_launch() {
  local sel="$1"
  local worktree="${2:-}"
  local mru="$_CLREPO_CACHE/mru"
  cd "$_CLREPO_BASE/$sel" || return
  _clrepo_sync "$(basename "$sel")" "$worktree"
  { printf '%s
' "$sel"; grep -vxF "$sel" "$mru" 2>/dev/null; } | head -10 > "$mru.tmp" && mv "$mru.tmp" "$mru"
```

- [ ] **Step 2: Syntax-check**

```bash
bash -n shell/clrepo.sh && echo OK
```

Expected: `OK`.

- [ ] **Step 3: End-to-end smoke (dry — don't actually launch claude)**

We can't easily run `_clrepo_launch` end-to-end without launching Claude. Instead, source the file and invoke the function up to the point of `claude`, then Ctrl-C. A safer alternative: inspect the call ordering by running just `_clrepo_sync` from the same cwd as a real invocation:

```bash
( source shell/clrepo.sh
  cd /home/freax/projects/repos/github/freaxnx01/public/config
  _clrepo_sync "$(basename "$PWD")"
  echo "[would now: MRU update, slot allocation, claude launch]"
)
```

Expected: silent (or yellow warning if the working tree is dirty), then the bracketed line.

- [ ] **Step 4: Commit**

```bash
git add shell/clrepo.sh
git commit -m "clrepo: call _clrepo_sync from _clrepo_launch after cd"
```

---

## Task 6: Update tab completion for `--no-sync`

**Why:** Discoverability. Users tab-complete flags rather than reading `--help`.

**Files:**
- Modify: `shell/clrepo.sh` — `_clrepo` completion function (currently around lines 976–993).

- [ ] **Step 1: Add `--no-sync` to the flags list**

Find this line (currently around line 980):

```bash
    local flags="-r --remote --refresh -D --delete -w --worktree -h --help"
```

Replace with:

```bash
    local flags="-r --remote --refresh -D --delete -w --worktree --no-sync --no-channel --slot --status --free -h --help"
```

(The original list omitted several flags that already exist in the parser. Adding them all here improves discoverability without changing parser behavior.)

- [ ] **Step 2: Verify completion**

```bash
( source shell/clrepo.sh
  COMP_WORDS=(clrepo --n)
  COMP_CWORD=1
  _clrepo
  printf '%s\n' "${COMPREPLY[@]}"
)
```

Expected output includes `--no-sync`, `--no-channel`.

- [ ] **Step 3: Commit**

```bash
git add shell/clrepo.sh
git commit -m "clrepo: add --no-sync (and other existing flags) to tab completion"
```

---

## Task 7: Final verification — bash LSP and full smoke run

**Why:** Per the spec's testing section: lint with bash-language-server and run the canonical smoke scenarios in one pass.

**Files:** None modified. Verification only.

- [ ] **Step 1: Run bash-language-server / shellcheck over the file**

Try in this order, take whichever is available:

```bash
# Preferred: via bash-language-server CLI if installed.
command -v bash-language-server >/dev/null && bash-language-server analyze shell/clrepo.sh

# Fallback: direct shellcheck (bash-language-server uses it internally).
command -v shellcheck >/dev/null && shellcheck -x shell/clrepo.sh
```

Expected: no NEW errors or warnings introduced by Tasks 1–6 vs. the pre-feature `main`. Pre-existing diagnostics from earlier code are out of scope.

If new diagnostics appear, fix them in `shell/clrepo.sh` and amend the appropriate task's commit (or add a follow-up commit).

- [ ] **Step 2: Up-to-date scenario**

```bash
( source shell/clrepo.sh
  cd /home/freax/projects/repos/github/freaxnx01/public/config
  _clrepo_sync "$(basename "$PWD")"
)
```

Expected: silent (assuming local matches origin/main).

- [ ] **Step 3: --no-sync silent scenario**

```bash
( source shell/clrepo.sh
  cd /home/freax/projects/repos/github/freaxnx01/public/config
  _CLREPO_NO_SYNC=1 _clrepo_sync "$(basename "$PWD")"
)
```

Expected: silent.

- [ ] **Step 4: Behind scenario**

```bash
mkdir -p /tmp/clrepo-final && cd /tmp/clrepo-final
rm -rf upstream clone
git init --quiet --bare upstream
git clone --quiet upstream clone
cd clone
git config user.email t@t && git config user.name t
echo a > a && git add a && git commit --quiet -m a
git push --quiet origin master 2>/dev/null || git push --quiet origin main
echo b > b && git add b && git commit --quiet -m b
git push --quiet
git reset --quiet --hard HEAD~1
( source /home/freax/projects/repos/github/freaxnx01/public/config/shell/clrepo.sh
  _clrepo_sync clone )
cd /tmp && rm -rf clrepo-final
```

Expected: `clrepo: pulled <sha>..<sha> on <branch>` line on stderr.

- [ ] **Step 5: Diverged scenario**

```bash
mkdir -p /tmp/clrepo-final && cd /tmp/clrepo-final
rm -rf upstream clone
git init --quiet --bare upstream
git clone --quiet upstream clone
cd clone
git config user.email t@t && git config user.name t
echo a > a && git add a && git commit --quiet -m a
br=$(git symbolic-ref --short HEAD)
git push --quiet -u origin "$br"
# Make upstream advance (simulated via second clone).
cd .. && git clone --quiet upstream other && cd other
git config user.email t@t && git config user.name t
echo c > c && git add c && git commit --quiet -m c
git push --quiet
cd ../clone
# Local diverges
echo b > b && git add b && git commit --quiet -m b
( source /home/freax/projects/repos/github/freaxnx01/public/config/shell/clrepo.sh
  _clrepo_sync clone )
cd /tmp && rm -rf clrepo-final
```

Expected: yellow `clrepo: <branch> diverged from origin/<branch>, skipping sync`.

- [ ] **Step 6: Final commit (if any fixups landed)**

```bash
git status
# If there are uncommitted fixups from Step 1:
git add shell/clrepo.sh
git commit -m "clrepo: address LSP diagnostics from sync feature"
```

If `git status` shows clean, skip the commit.

---

## Self-Review Notes

Spec coverage:
- Sync semantics (Section "Sync semantics") → Task 3.
- Skip conditions table → Task 3 (every row covered: `--no-sync`, tmux reattach, detached HEAD, no upstream, dirty, fetch fail, diverged).
- New `--no-sync` flag → Tasks 4 + 6.
- Help text update → Task 4.
- Tab completion update → Task 6.
- Integration point (post-`cd`, pre-MRU) → Task 5.
- `_clrepo_tmux_session_name` shared helper → Task 2.
- Error handling never fails launch → Task 3 function body (every error path returns 0).
- Manual smoke + LSP testing → Task 7.

No placeholders, all code blocks complete, all paths absolute.
