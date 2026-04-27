# clrepo pull/sync on startup — design

**Date:** 2026-04-27
**Component:** `shell/clrepo.sh`

## Problem

`clrepo <name>` cd's into a repo and launches Claude Code. The local checkout may be hours or days behind the remote — work then begins on a stale tree, sometimes producing duplicate or conflicting changes against commits that already exist upstream.

## Goal

Bring the active branch up to date with its upstream before Claude launches, when (and only when) doing so is safe and unambiguous. Never modify the working tree silently; never block startup on a network problem.

## Non-goals

- No multi-branch sync. Only the currently checked-out branch.
- No worktree-aware pull beyond what `git pull --ff-only` in the main checkout already gives. Worktrees inherit the updated refs once the main repo has fetched.
- No automatic stash, rebase, merge-conflict resolution, or `git pull --rebase`. Those decisions stay with the user.
- No background fetch. Inline only.
- No persistent config (env var, dotfile). The opt-out is a per-invocation flag.
- No change to the remote-listing cache (`remote.list`, `repo-meta.json`) — that is independent of the active checkout.

## Sync semantics

Fast-forward only. Concretely, in the repo's main directory after `cd`:

1. `timeout 10 git fetch --quiet`
2. Compare `HEAD` to `@{u}`:
   - equal → no-op, silent
   - local ahead-only → no-op, silent (unpushed work is the user's business)
   - local behind-only → `git merge --ff-only --quiet @{u}`, print one line
   - diverged → warn, do nothing

Successful pull prints exactly one line to stderr:

```
clrepo: pulled <short-old>..<short-new> on <branch>
```

## Skip conditions

The sync step is a no-op (with a one-line reason on stderr) when any of these hold:

| Condition | Reason printed |
|---|---|
| `--no-sync` was passed | (silent — explicit user opt-out) |
| Reattaching an existing tmux session for this repo+worktree | (silent — claude is already running, sync would be moot) |
| Detached HEAD | `detached HEAD, skipping sync` |
| Current branch has no upstream | `no upstream for <branch>, skipping sync` |
| Working tree has staged or unstaged changes to tracked files | `dirty working tree, skipping sync` |
| `git fetch` fails or times out | `fetch failed or timed out, skipping sync` |
| Branch has diverged from upstream | `<branch> diverged from <upstream>, skipping sync` |

All non-silent skip messages are printed in yellow (`\033[33m … \033[0m`) prefixed `clrepo:` so they are visible but not alarming. They go to stderr so they don't pollute any stdout consumer.

## Surface

**New flag:**

- `--no-sync` — skip the pull for this invocation. Useful when offline, on a slow link, or when you explicitly want to start from the local state.

**No** new env var, no settings file. If a user wants permanent opt-out, they alias `clrepo` to `clrepo --no-sync`.

**Help text** (`-h`/`--help`) gains one line:

```
      --no-sync         skip the upstream fast-forward pull on startup
```

**Tab completion:** add `--no-sync` to the flags list in `_clrepo`.

## Integration point

A new function `_clrepo_sync` is added in `shell/clrepo.sh`, defined immediately above `_clrepo_launch`.

It is called from `_clrepo_launch` immediately after `cd "$_CLREPO_BASE/$sel"` and before the MRU update — so:

1. The sync sees the correct working directory.
2. MRU is only bumped if we actually proceed past the cd.
3. Slot allocation, Telegram setup, and tmux logic all see refs that are already up to date.

The reattach-skip check uses the *same* tmux session-name derivation as `_clrepo_launch` so the two stay in sync. To avoid drift, the session name is computed by a small shared helper `_clrepo_tmux_session_name "$repo" "$worktree"` used both by `_clrepo_sync` (skip check) and `_clrepo_launch` (session create/attach).

## Function shape

```bash
_clrepo_tmux_session_name() {
  local s="$1"
  [ -n "${2:-}" ] && s="$1-$2"
  printf '%s' "${s//[^A-Za-z0-9_-]/_}"
}

_clrepo_warn() {
  printf '\033[33mclrepo: %s\033[0m\n' "$*" >&2
}

_clrepo_sync() {
  local repo="$1" worktree="${2:-}"
  [ "${_CLREPO_NO_SYNC:-0}" = 1 ] && return 0

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
    return 0  # local ahead — fine
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

## Argument-parser changes in `clrepo()`

- Add local: `_CLREPO_NO_SYNC=0` alongside the other locals at the top.
- Add case branch: `--no-sync) _CLREPO_NO_SYNC=1; shift ;;`
- Add help line as shown above.

## `_clrepo_launch` changes

Right after `cd "$_CLREPO_BASE/$sel" || return` and before the `mru` block:

```bash
_clrepo_sync "$(basename "$sel")" "$worktree"
```

Refactor `_clrepo_launch` to use the new `_clrepo_tmux_session_name` helper instead of its inline derivation, so both call sites are consistent.

## Error handling

Sync never fails the launch. Every error path returns 0 after printing a warning (or staying silent). The launch proceeds regardless.

## Testing

Manual smoke tests against the very repo this spec lives in:

1. **Up-to-date** — `clrepo config` from a clean tree at the tip of `main` → silent, claude launches.
2. **Behind** — reset to a prior commit, `clrepo config` → see "pulled abc..def on main" line, then claude launches with current tip.
3. **Dirty** — `touch x; clrepo config` → see "dirty working tree, skipping sync" warning, claude launches.
4. **Diverged** — create a local commit, fetch shows upstream also moved → see "main diverged from origin/main, skipping sync" warning, claude launches.
5. **Detached HEAD** — `git checkout HEAD~1` then `clrepo config` → see "detached HEAD, skipping sync" warning.
6. **No upstream** — `git checkout -b throwaway`, `clrepo config` → see "no upstream for throwaway, skipping sync" warning.
7. **`--no-sync`** — `clrepo --no-sync config` → silent, no fetch.
8. **Tmux reattach** (skip if not in SSH context) — start a session, detach, re-run → no fetch second time.
9. **Lint** — `bash-language-server` (LSP) clean over `shell/clrepo.sh`.

No unit-test framework exists for this script; verification is by manual smoke + LSP.

## Out of scope (could be added later)

- Background fetch with a `clrepo: behind by N` indicator if the user prefers a non-mutating default.
- A `clrepo --sync-all` housekeeping command that walks every cloned repo and runs the same sync.
- A "stale-repo report" that surfaces all cloned repos behind their upstream — useful for batch cleanup but a separate UX from per-launch sync.
