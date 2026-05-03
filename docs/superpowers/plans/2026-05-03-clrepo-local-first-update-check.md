# clrepo local-first update check — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `_clrepo_check_latest` read the on-disk `clrepo.sh` first; fall back to the existing remote curl only when the on-disk path can't be resolved or read.

**Architecture:** Single in-place rewrite of one function (`shell/clrepo.sh:1298`). The new prelude resolves `BASH_SOURCE[0]` via `readlink -f`, greps `_CLREPO_VERSION` from the on-disk file, and either prints the existing hint or returns silently. Existing TTL-cached remote curl path is preserved verbatim as the `else` branch for installs where the script lives outside a readable file path. No new files, no new commands, no new flags.

**Tech Stack:** Bash 5, `grep`, `sed`, `readlink`. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-05-03-clrepo-local-first-update-check-design.md`

---

## File Structure

- **Modify:** `shell/clrepo.sh`
  - Line 25: bump `_CLREPO_VERSION` from `1.13.0` → `1.13.1` (per `CLAUDE.md`).
  - Lines 1296–1320: rewrite the body of `_clrepo_check_latest`.
- **No test files** — this repo has no automated test suite for shell code. Verification is manual, performed in a fresh interactive shell on `claude-dev`.

## Note on TDD in this plan

The repo has no shell-test harness (no `bats`, no shunit2, no shell tests anywhere). Adding one for a 20-line function change would dwarf the change itself — explicit YAGNI. Verification therefore consists of three scripted manual scenarios (Task 2), each with a precise expected output and an objective network-side check (mtime of the cache file).

---

### Task 1: Rewrite `_clrepo_check_latest` and bump version

**Files:**
- Modify: `shell/clrepo.sh:25` (version bump)
- Modify: `shell/clrepo.sh:1296-1320` (function body)

- [ ] **Step 1: Bump `_CLREPO_VERSION`**

In `shell/clrepo.sh`, change line 25 from:

```bash
_CLREPO_VERSION="1.13.0"
```

to:

```bash
_CLREPO_VERSION="1.13.1"
```

- [ ] **Step 2: Replace the body of `_clrepo_check_latest`**

In `shell/clrepo.sh`, replace the entire function (currently lines 1296–1320) with:

```bash
# Hint if a newer _CLREPO_VERSION is available. Local-first: check the
# on-disk clrepo.sh that this shell was sourced from (kept current with
# origin by _clrepo_autosync). Fall back to a TTL-gated remote curl only
# when the on-disk path can't be resolved or read.
_clrepo_check_latest() {
  local script="${BASH_SOURCE[0]}"
  if command -v readlink >/dev/null 2>&1; then
    script=$(readlink -f "$script" 2>/dev/null || echo "$script")
  fi

  if [ -r "$script" ]; then
    local on_disk
    on_disk=$(grep -m1 '^_CLREPO_VERSION=' "$script" 2>/dev/null \
              | sed -E 's/^_CLREPO_VERSION="?([^"]+)"?.*/\1/')
    if [ -n "$on_disk" ]; then
      if _clrepo_version_gt "$on_disk" "$_CLREPO_VERSION"; then
        echo "clrepo: new version $on_disk available (you have $_CLREPO_VERSION) — run \`clrepo update\`" >&2
      fi
      return 0
    fi
  fi

  # Fallback: on-disk path missing/unreadable/malformed. Use the cached
  # remote check (background-refresh, mtime-gated by TTL).
  local cache="$_CLREPO_CACHE/latest-version"
  local age
  age=$(( $(date +%s) - $(stat -c %Y "$cache" 2>/dev/null || echo 0) ))
  if [ ! -f "$cache" ] || [ "$age" -gt "$_CLREPO_UPDATE_TTL" ]; then
    (
      flock -n 9 || exit 0
      local v
      v=$(curl -fsSL --max-time 5 "$_CLREPO_RAW_URL" 2>/dev/null \
            | grep -m1 '^_CLREPO_VERSION=' \
            | sed -E 's/^_CLREPO_VERSION="?([^"]+)"?.*/\1/')
      [ -n "$v" ] && printf '%s\n' "$v" > "$cache"
    ) 9>"$_CLREPO_CACHE/latest-warm.lock" </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null || true
  fi
  [ -f "$cache" ] || return 0
  local latest
  latest=$(cat "$cache" 2>/dev/null)
  [ -z "$latest" ] && return 0
  if _clrepo_version_gt "$latest" "$_CLREPO_VERSION"; then
    echo "clrepo: new version $latest available (you have $_CLREPO_VERSION) — run \`clrepo update\`" >&2
  fi
}
```

Notes for the implementer:
- The fallback branch (after `# Fallback:` comment) is a verbatim copy of today's body — only the prelude is new logic.
- Reuses `_clrepo_version_gt` (defined just above the function, `shell/clrepo.sh:1289`).
- Uses the same `readlink -f` pattern already in `_clrepo_update` (`shell/clrepo.sh:1326-1328`) for consistency.
- `[ -r "$script" ]` covers both "file doesn't exist" and "file unreadable" without separate branches.
- Empty `on_disk` (no `_CLREPO_VERSION` line found) drops through to the fallback rather than returning silently — handles a corrupted partial copy.

- [ ] **Step 3: Lint check**

Run from the repo root:

```bash
bash -n shell/clrepo.sh && echo "syntax OK"
```

Expected output: `syntax OK`

If `shellcheck` is available:

```bash
shellcheck -S warning shell/clrepo.sh 2>&1 | grep -A2 '_clrepo_check_latest' || echo "no warnings in target function"
```

Expected: `no warnings in target function` (pre-existing warnings elsewhere in the file are not in scope for this change).

---

### Task 2: Manual verification on `claude-dev`

**Files:** none modified — read-only verification.

These steps must run interactively in a shell with `clrepo.sh` sourced from the local config repo (the developer's normal setup). They use a temporary cache directory so they don't pollute the real `~/.cache/clrepo`.

- [ ] **Step 1: Set up an isolated cache and source the modified script**

```bash
export _CLREPO_TEST_CACHE="$(mktemp -d)"
# Open a fresh bash subshell so we don't disturb the parent shell's clrepo:
bash --rcfile <(cat <<'RC'
. ~/.bashrc
export _CLREPO_CACHE="$_CLREPO_TEST_CACHE"
mkdir -p "$_CLREPO_CACHE"
. ~/projects/repos/github/freaxnx01/public/config/shell/clrepo.sh
RC
)
```

(All subsequent steps run inside this subshell. `_CLREPO_CACHE` is the per-instance cache path used by `_clrepo_check_latest`.)

- [ ] **Step 2: Scenario A — up-to-date (no hint, no curl)**

In the subshell:

```bash
ls "$_CLREPO_CACHE"/latest-version 2>&1   # expect: No such file or directory
_clrepo_check_latest
echo "exit: $?"
ls "$_CLREPO_CACHE"/latest-version 2>&1   # still expect: No such file or directory
```

Expected:
- No `clrepo:` line printed.
- `exit: 0`.
- `latest-version` cache file does **not** appear (proof no remote curl ran).

- [ ] **Step 3: Scenario B — local edit ahead of in-memory**

Still in the subshell, simulate the developer mid-edit by writing a temp copy of `clrepo.sh` with a bumped version, then point the function at it. The cleanest way is to rebind `BASH_SOURCE` indirectly by re-sourcing from a temp file:

```bash
TMP_SCRIPT=$(mktemp --suffix=.sh)
sed 's/^_CLREPO_VERSION="1.13.1"/_CLREPO_VERSION="9.99.99"/' \
  ~/projects/repos/github/freaxnx01/public/config/shell/clrepo.sh > "$TMP_SCRIPT"
# Re-source the script from TMP_SCRIPT so BASH_SOURCE[0] points there.
# Disable alias expansion (same defensive pattern as _clrepo_update).
shopt -u expand_aliases
. "$TMP_SCRIPT"
# Now reload the in-memory version from the original (so file is "ahead" of memory):
_CLREPO_VERSION="1.13.1"
_clrepo_check_latest
echo "exit: $?"
ls "$_CLREPO_CACHE"/latest-version 2>&1
```

Expected:
- One line on stderr: `clrepo: new version 9.99.99 available (you have 1.13.1) — run `clrepo update``
- `exit: 0`.
- No `latest-version` cache file (still no remote curl).

Cleanup:

```bash
rm -f "$TMP_SCRIPT"
```

- [ ] **Step 4: Scenario C — fallback to remote curl**

```bash
# Simulate "script lives at unreadable path": copy clrepo.sh to a temp path,
# source it, then make it unreadable so the local-first branch fails.
TMP_SCRIPT=$(mktemp --suffix=.sh)
cp ~/projects/repos/github/freaxnx01/public/config/shell/clrepo.sh "$TMP_SCRIPT"
shopt -u expand_aliases
. "$TMP_SCRIPT"
chmod 000 "$TMP_SCRIPT"

rm -f "$_CLREPO_CACHE"/latest-version "$_CLREPO_CACHE"/latest-warm.lock
_clrepo_check_latest
echo "exit: $?"
sleep 6   # give the backgrounded curl up to 5s + buffer
ls -l "$_CLREPO_CACHE"/latest-version 2>&1
```

Expected:
- `exit: 0` (function returns immediately; curl runs in background).
- After the sleep, `latest-version` file exists and contains the published version (proof the fallback branch ran the remote curl).

Cleanup:

```bash
chmod 600 "$TMP_SCRIPT" && rm -f "$TMP_SCRIPT"
exit   # leave the test subshell
rm -rf "$_CLREPO_TEST_CACHE"
unset _CLREPO_TEST_CACHE
```

- [ ] **Step 5: Sanity-source in your real shell**

Back in the parent shell, re-source the modified script and confirm the version reports correctly:

```bash
. ~/projects/repos/github/freaxnx01/public/config/shell/clrepo.sh
clrepo --version
```

Expected: `clrepo 1.13.1`.

---

### Task 3: Commit

**Files:**
- `shell/clrepo.sh` (both changes)

- [ ] **Step 1: Verify diff is clean**

```bash
git -C ~/projects/repos/github/freaxnx01/public/config diff shell/clrepo.sh
```

Expected: only the version-line change and the rewritten `_clrepo_check_latest` body. No unrelated edits.

- [ ] **Step 2: Stage and commit**

```bash
cd ~/projects/repos/github/freaxnx01/public/config
git add shell/clrepo.sh
git commit -m "$(cat <<'EOF'
feat(clrepo): local-first update check (closes #6)

_clrepo_check_latest now reads BASH_SOURCE[0] (kept current with origin
by _clrepo_autosync) before falling back to the cached remote curl.
Eliminates the network round-trip in the developer's normal workflow,
where the on-disk clrepo.sh is the source of truth.

Bumps _CLREPO_VERSION 1.13.0 -> 1.13.1.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 3: Confirm**

```bash
git log -1 --stat
```

Expected: one commit, one file changed (`shell/clrepo.sh`), insertions/deletions reflecting the function rewrite + version bump.

---

## Self-review (already performed)

- **Spec coverage:** every spec section maps to a task. Local-first prelude → Task 1 Step 2. Fallback preservation → same step (verbatim copy). Edge-case table → covered by `[ -r ]` test (missing/unreadable) and empty-`on_disk` drop-through (malformed). Version bump → Task 1 Step 1. Manual scenarios → Task 2 Steps 2–4 (one per scenario in the spec).
- **Placeholder scan:** no TBD/TODO; every code step shows complete code; every command shows expected output.
- **Type/name consistency:** `_clrepo_check_latest`, `_clrepo_version_gt`, `_CLREPO_VERSION`, `_CLREPO_CACHE`, `_CLREPO_UPDATE_TTL`, `_CLREPO_RAW_URL` all match the existing identifiers in `shell/clrepo.sh`.
