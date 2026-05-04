# clrepo session picker (`--attach`) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `clrepo -a|--attach` flag that opens an fzf picker over live tmux-backed sessions (the rows `--status` already shows) and reattaches to the selection — zero retyping of repo / worktree.

**Architecture:** All changes live in `shell/clrepo.sh`. (1) Extract the dead-slot reconcile block currently inlined in `_clrepo_slot_status` into a new `_clrepo_reconcile_slots` helper so two callers can share it. (2) Add `_clrepo_attach_pick` next to `_clrepo_slot_status`: it calls the helper, reads `slots.json`, filters to entries with a non-empty `session` field, and either errors (0 live), auto-attaches (1 live), or runs fzf (2+ live). (3) Add `--attach`/`-a` parsing in `clrepo()`, a combo-rejection guard that errors if any other flag/positional was passed, plus help-text and tab-completion updates. No new files, no new state, no new dependencies.

**Tech Stack:** Bash 5, `python3` (already used by `_clrepo_slot_status`), `fzf`, `tmux`, `awk`. All present today.

**Spec:** `docs/superpowers/specs/2026-05-04-clrepo-session-picker-design.md` (issue [#18](https://github.com/freaxnx01/config/issues/18))

---

## File Structure

- **Modify:** `shell/clrepo.sh` (sole source file touched)
  - Line 25: bump `_CLREPO_VERSION` from `1.15.0` → `1.16.0` (new feature → minor per `CLAUDE.md`).
  - Lines 1082–1150: refactor `_clrepo_slot_status` to call the new `_clrepo_reconcile_slots`.
  - New function `_clrepo_reconcile_slots` inserted just above `_clrepo_slot_status` (~line 1080).
  - New function `_clrepo_attach_pick` inserted just below `_clrepo_slot_status` (~line 1151).
  - Line 1458: add `mode_attach=0` to the existing local-declarations list in `clrepo()`.
  - Inside the parser case-loop (around line 1469): add `-a|--attach` case.
  - After `set -- "${pos[@]}"` (line 1526): add the combo-rejection + dispatch block.
  - Line 1510 area (help heredoc): add `-a, --attach` line under the slot-management group.
  - Line 1698 (tab completion `flags=`): add `-a` and `--attach`.
- **No new files, no test files.** This repo has no shell-test harness — verification is the manual matrix from the spec, run interactively.

## Note on TDD in this plan

The repo has no shell-test harness (no `bats`, no `shunit2`). Adding one for this change would dwarf the change itself — explicit YAGNI, matching the precedent set by the prior `_clrepo_check_latest` plan. Verification is the 10-row manual matrix from the spec (Task 5 below), each scenario with a precise expected output.

The behavior-preserving refactor (Task 1) gets a stricter check: the `--status` output must be byte-identical before vs after, captured via diff.

---

### Task 1: Extract `_clrepo_reconcile_slots` helper

**Files:**
- Modify: `shell/clrepo.sh:1082-1150` (`_clrepo_slot_status` body)
- Insert new function above `_clrepo_slot_status` (~line 1080)

This is a pure refactor — no behavior change. Capture `--status` output before changing anything so we can diff after.

- [ ] **Step 1: Snapshot `--status` output for diff baseline**

In a shell where `clrepo.sh` is sourced (i.e. your normal interactive shell on `claude-dev`):

```bash
clrepo --status > /tmp/clrepo-status-before.txt 2>&1
echo "exit: $?"
wc -l /tmp/clrepo-status-before.txt
```

Expected: a non-empty file with the current slot table. Note the exit code and line count — the post-refactor run must match.

- [ ] **Step 2: Insert the new `_clrepo_reconcile_slots` function**

In `shell/clrepo.sh`, immediately above the `_clrepo_slot_status` definition (currently `# Print slot status table.` comment at ~line 1081), insert:

```bash
# Reconcile dead slots in slots.json: tmux session is source of truth when
# the slot record has one, otherwise fall back to PID liveness for
# foreground-mode records. Idempotent and silent on no-op. Both
# _clrepo_slot_status and _clrepo_attach_pick call this before reading.
_clrepo_reconcile_slots() {
  python3 -c "
import json, os, subprocess
f = '$_CLREPO_SLOTS_FILE'
MAX = $_CLREPO_MAX_SLOTS
with open(f) as fh: d = json.load(fh)
slots = d.setdefault('slots', {})
for k, v in list(slots.items()):
    if not v: continue
    sess = v.get('session') or ''
    if sess:
        alive = subprocess.run(['tmux', 'has-session', '-t', sess],
                               stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL).returncode == 0
    else:
        try: os.kill(int(v.get('pid', 0)), 0); alive = True
        except (ProcessLookupError, ValueError): alive = False
        except PermissionError: alive = True
    if not alive:
        slots[k] = None
# Drop empty entries whose key isn't a valid slot number (non-numeric, negative,
# or > MAX_SLOTS) — leftover from manual edits or shrunk MAX. Live entries are
# preserved so we never orphan a running session's record.
for k in list(slots.keys()):
    if slots[k] is not None: continue
    try: n = int(k)
    except ValueError: del slots[k]; continue
    if n < 0 or n > MAX: del slots[k]
with open(f, 'w') as fh: json.dump(d, fh, indent=2)
" 2>/dev/null
}
```

The python heredoc is a verbatim copy of the block currently inlined at `shell/clrepo.sh:1087-1115`, including the `2>/dev/null` swallow. The leading comment is new; nothing else is.

- [ ] **Step 3: Replace the inlined reconcile in `_clrepo_slot_status`**

In `shell/clrepo.sh`, find the current `_clrepo_slot_status` (begins `_clrepo_slot_status() {`, currently at line 1082). Replace the body section spanning the comment `# Reconcile dead slots ...` through the closing `" 2>/dev/null` of the first python invocation (lines 1085–1115) with a single call:

Before (existing):

```bash
_clrepo_slot_status() {
  _clrepo_slots_init

  # Reconcile dead slots (tmux session is source of truth when recorded;
  # otherwise fall back to PID liveness for foreground-mode records)
  python3 -c "
import json, os, subprocess
... (entire block)
" 2>/dev/null

  python3 -c "
import json, time
... (printing block)
```

After:

```bash
_clrepo_slot_status() {
  _clrepo_slots_init
  _clrepo_reconcile_slots

  python3 -c "
import json, time
... (printing block — UNCHANGED)
```

Only the reconcile python block is removed; the second python block (the table printer) is untouched. Net diff: ~30 lines removed from `_clrepo_slot_status`, replaced by one function call.

- [ ] **Step 4: Lint check**

```bash
bash -n shell/clrepo.sh && echo "syntax OK"
```

Expected: `syntax OK`

- [ ] **Step 5: Re-source and diff `--status` output**

```bash
. ~/projects/repos/github/freaxnx01/public/config/shell/clrepo.sh
clrepo --status > /tmp/clrepo-status-after.txt 2>&1
echo "exit: $?"
diff /tmp/clrepo-status-before.txt /tmp/clrepo-status-after.txt && echo "IDENTICAL"
```

Expected: `IDENTICAL`. Same exit code as Step 1.

If diff shows any difference: the refactor was not behavior-preserving. Stop and inspect — the most likely cause is an accidental edit to the second python block.

Cleanup:

```bash
rm -f /tmp/clrepo-status-before.txt /tmp/clrepo-status-after.txt
```

---

### Task 2: Add `_clrepo_attach_pick` function

**Files:**
- Modify: `shell/clrepo.sh` — insert new function immediately *after* `_clrepo_slot_status` (i.e. between `_clrepo_slot_status` and `_clrepo_print_last`, at what is currently ~line 1151).

- [ ] **Step 1: Insert `_clrepo_attach_pick`**

Insert this function after the closing `}` of `_clrepo_slot_status`:

```bash
# Pick a live tmux-backed session via fzf and reattach. Reads slots.json
# (same source as --status), filters to records with a non-empty `session`
# field. 0 live → error, 1 live → auto-attach (no picker), 2+ → fzf.
# Foreground-mode records (no `session` field) are not attachable and are
# excluded. Standalone — no other flags, no positional args (validated by
# the caller in clrepo()).
_clrepo_attach_pick() {
  _clrepo_slots_init
  _clrepo_reconcile_slots

  # Emit one TSV row per live, tmux-backed slot:
  #   <slot>\t<repo>\t<worktree-or-empty>\t<age>\t<session>
  local rows
  rows=$(python3 -c "
import json, time
with open('$_CLREPO_SLOTS_FILE') as f: d = json.load(f)
slots = d.get('slots', {})
now = int(time.time())
out = []
for k in sorted(slots.keys(), key=lambda s: int(s) if s.isdigit() else 999):
    v = slots.get(k)
    if not v: continue
    sess = v.get('session') or ''
    if not sess: continue  # foreground-mode: not attachable
    repo = v.get('repo', '')
    wt = v.get('worktree') or ''
    sa = v.get('started_at', 0)
    age = now - sa if sa else 0
    h, m = divmod(age // 60, 60)
    age_s = f'{h}h{m:02d}m' if sa else '—'
    out.append('\t'.join([k, repo, wt, age_s, sess]))
print('\n'.join(out))
" 2>/dev/null)

  # Strip a trailing-only newline from python's print so wc -l on empty is 0.
  local count=0
  [ -n "$rows" ] && count=$(printf '%s\n' "$rows" | grep -c .)

  if [ "$count" = 0 ]; then
    echo "clrepo: no live sessions" >&2
    return 1
  fi

  local session
  if [ "$count" = 1 ]; then
    # Single live session: auto-attach, no picker.
    session=$(printf '%s' "$rows" | awk -F'\t' '{print $5; exit}')
  else
    # 2+ live: fzf picker. Display column is human-formatted; the exact
    # session name rides along as a trailing tab-separated field for
    # unambiguous extraction (same trick as the meta-search picker).
    local out
    out=$(printf '%s\n' "$rows" \
      | awk -F'\t' 'BEGIN{OFS=""} { wt = ($3=="" ? "—" : $3); \
          printf "s%-3s %-30s %-10s %-12s\t%s\n", $1, $2, wt, $4, $5 }' \
      | fzf --height=40% --reverse --prompt='session> ' \
            -d $'\t' --with-nth=1) || return
    session=$(printf '%s' "$out" | awk -F'\t' '{print $2}')
  fi

  [ -z "$session" ] && return
  tmux attach-session -t "$session"
}
```

Notes for the implementer:

- The python block's `2>/dev/null` matches `_clrepo_slot_status`'s tolerance for malformed/missing `slots.json` — a python exception swallows silently and `rows` stays empty, falling through to the "no live sessions" path. Edge case 1 in the spec.
- `count` is computed via `grep -c .` so a file with only blank lines also yields 0.
- `key=lambda s: int(s) if s.isdigit() else 999` mirrors the defensive sort in `_clrepo_slot_status` — non-numeric keys (which reconcile already drops) sink to the bottom rather than crashing the sort.
- Foreground-mode records (no `session` field) are filtered with `if not sess: continue`. Edge case 2 + spec scenario 6.
- `|| return` after the fzf invocation means Ctrl-C exits the function with fzf's non-zero status. Edge case 4.
- No `_clrepo_print_last`, no slot allocation, no telegram. Pure attach (spec design step 5).

- [ ] **Step 2: Lint check**

```bash
bash -n shell/clrepo.sh && echo "syntax OK"
```

Expected: `syntax OK`

- [ ] **Step 3: Smoke-test the function in isolation**

Re-source the script and call the function directly (before the `clrepo` flag is wired):

```bash
. ~/projects/repos/github/freaxnx01/public/config/shell/clrepo.sh
_clrepo_attach_pick
echo "exit: $?"
```

Expected behavior depends on your current slot occupancy:

- All slots free → `clrepo: no live sessions` on stderr, `exit: 1`.
- Exactly 1 live session → tmux attaches immediately. Detach with `Ctrl-b d`; `exit: 0`.
- 2+ live → fzf picker appears. Pick one → attach. Detach. Or Ctrl-C → `exit: 130`.

If your environment has 0 live sessions and you want to exercise the auto-attach + picker paths now, defer to Task 5 (manual verification matrix).

---

### Task 3: Wire `--attach` into `clrepo()` parser, help, completion

**Files:**
- Modify: `shell/clrepo.sh:1458` (locals list)
- Modify: `shell/clrepo.sh` parser case-loop (~line 1461–1525)
- Modify: `shell/clrepo.sh` post-parser block (insert after `set -- "${pos[@]}"`, currently line 1526)
- Modify: `shell/clrepo.sh` help heredoc (~line 1510, slot-management group)
- Modify: `shell/clrepo.sh:1698` (tab-completion `flags=` string)

- [ ] **Step 1: Add `mode_attach=0` to locals**

Find line 1458:

```bash
  local with_remote=0 force_refresh=0 mode_delete=0 worktree="" editor="" remote_control=1 _CLREPO_NO_CHANNEL=0 _CLREPO_FORCED_SLOT="" _CLREPO_NO_SYNC=0
```

Replace with (append `mode_attach=0` at the end):

```bash
  local with_remote=0 force_refresh=0 mode_delete=0 worktree="" editor="" remote_control=1 _CLREPO_NO_CHANNEL=0 _CLREPO_FORCED_SLOT="" _CLREPO_NO_SYNC=0 mode_attach=0
```

- [ ] **Step 2: Add the `-a|--attach` parser case**

In the case-loop (currently lines 1461–1524), find the `--status` line:

```bash
      --status)       _clrepo_slot_status; return ;;
```

Insert a new case directly above it:

```bash
      -a|--attach)    mode_attach=1; shift ;;
```

Order matters cosmetically only — placing it next to `--status` keeps the slot-management cases grouped, matching the spec.

- [ ] **Step 3: Add the combo-rejection + dispatch block**

Find the line just after the case-loop end (`done`) and `set -- "${pos[@]}"`. Currently:

```bash
    esac
  done
  set -- "${pos[@]}"

  mkdir -p "$_CLREPO_CACHE"
```

Insert the dispatch block between `set -- "${pos[@]}"` and `mkdir -p "$_CLREPO_CACHE"`:

```bash
  set -- "${pos[@]}"

  if [ "$mode_attach" = 1 ]; then
    local bad=""
    [ "$with_remote" = 1 ]            && bad="${bad:+$bad, }-r/--remote/--refresh"
    [ "$mode_delete" = 1 ]            && bad="${bad:+$bad, }-D/--delete"
    [ -n "$worktree" ]                && bad="${bad:+$bad, }-w/--worktree"
    [ -n "$editor" ]                  && bad="${bad:+$bad, }-c/-p"
    [ "$_CLREPO_NO_CHANNEL" = 1 ]     && bad="${bad:+$bad, }--no-channel"
    [ "$_CLREPO_NO_SYNC" = 1 ]        && bad="${bad:+$bad, }--no-sync"
    [ -n "$_CLREPO_FORCED_SLOT" ]     && bad="${bad:+$bad, }--slot"
    [ "$remote_control" != 1 ]        && bad="${bad:+$bad, }--no-rc"
    if [ -n "$bad" ]; then
      echo "clrepo: --attach takes no other flags (got: $bad). Run \`clrepo <repo>\` to launch." >&2
      return 2
    fi
    if [ ${#pos[@]} -gt 0 ]; then
      echo "clrepo: --attach takes no positional args (got: ${pos[*]}). Run \`clrepo <repo>\` to launch." >&2
      return 2
    fi
    _clrepo_attach_pick
    return
  fi

  mkdir -p "$_CLREPO_CACHE"
```

Notes for the implementer:

- `[ "$remote_control" != 1 ]` only fires when the user passed `--no-rc`/`--no-remote-control` (which sets it to 0). The default is 1, so a bare `--rc` is silently accepted. This is intentional per spec ("we can't distinguish 'user passed --rc (no-op default)' from 'user passed nothing' without parser changes — and that's fine").
- The spec's example error message names `-r/--remote/--refresh` for `with_remote=1`. Note that `--refresh` also sets `with_remote=1` *and* `force_refresh=1`; we don't bother detecting `--refresh` separately since the user gets a clear-enough hint either way.
- Returning `2` matches the existing argument-error convention (e.g. `--slot` and `--free` without their value at lines 1467, 1471).

- [ ] **Step 4: Add the help-text line**

In the help heredoc, find the slot-management group (currently around line 1510):

```bash
  --slot N              force a specific slot (1..N)
  --no-channel          legacy mode, no slot allocation, no Telegram
  --no-sync             skip the upstream fast-forward pull on startup
  --status              show slot status table
  --free N              force-free slot N (escape hatch)
```

Insert the `--attach` line directly above `--status` (mirroring source order; keeps reattach grouped with status as a "look at running sessions" pair):

```bash
  --slot N              force a specific slot (1..N)
  --no-channel          legacy mode, no slot allocation, no Telegram
  --no-sync             skip the upstream fast-forward pull on startup
  -a, --attach          fzf picker over live sessions; reattach to selection
  --status              show slot status table
  --free N              force-free slot N (escape hatch)
```

- [ ] **Step 5: Update tab-completion**

Find line 1698:

```bash
    local flags="-r --remote --refresh -D --delete -c --code -p --copilot --remote-control --rc -w --worktree --no-sync --no-channel --slot --status --free -V --version -h --help"
```

Insert `-a --attach` between `--free` and `-V`:

```bash
    local flags="-r --remote --refresh -D --delete -c --code -p --copilot --remote-control --rc -w --worktree --no-sync --no-channel --slot --status --free -a --attach -V --version -h --help"
```

- [ ] **Step 6: Lint check**

```bash
bash -n shell/clrepo.sh && echo "syntax OK"
```

Expected: `syntax OK`

If `shellcheck` is available:

```bash
shellcheck -S warning shell/clrepo.sh 2>&1 \
  | grep -A2 -E '_clrepo_attach_pick|_clrepo_reconcile_slots|mode_attach' \
  || echo "no warnings in changed code"
```

Expected: `no warnings in changed code` (pre-existing warnings elsewhere in the file are not in scope).

---

### Task 4: Bump `_CLREPO_VERSION`

**Files:**
- Modify: `shell/clrepo.sh:25`

Per `CLAUDE.md`: any change to `shell/clrepo.sh` requires a `_CLREPO_VERSION` bump per semver. This is a new feature → minor bump.

- [ ] **Step 1: Bump version**

In `shell/clrepo.sh`, change line 25 from:

```bash
_CLREPO_VERSION="1.15.0"
```

to:

```bash
_CLREPO_VERSION="1.16.0"
```

- [ ] **Step 2: Verify**

```bash
. ~/projects/repos/github/freaxnx01/public/config/shell/clrepo.sh
clrepo --version
```

Expected: `clrepo 1.16.0`.

---

### Task 5: Manual verification matrix

**Files:** none modified — read-only verification on a sourced shell.

This implements the verification table from the spec. Run each scenario in your normal interactive shell on `claude-dev` (where `clrepo.sh` is sourced).

Setting up the test fixtures:

- "Live session" = run `clrepo <some-repo>` (or `clrepo <repo> -w <wt>`) in another terminal/tmux pane, then detach with `Ctrl-b d`. The slot stays allocated.
- "Free slot" = nothing required; default state.
- "Stale slot record" = manually scribble into `~/.cache/clrepo/slots.json`: pick a free slot, set its value to a fake record with a non-existent `session` name (e.g. `"session": "ghost_session"`). Reconcile will prune it on the next call.
- "Foreground-mode record" = a slot record where `v.get('session')` is empty/missing. You can simulate by editing `slots.json` to add a record with `pid` set (to your shell's `$$`, so it's "alive") but **no** `session` field.

Always `cp ~/.cache/clrepo/slots.json /tmp/slots.bak` before editing, and restore at the end. Don't kill the live ones.

- [ ] **Step 1: Scenario 1 — all slots free**

Free any live slots first (`clrepo --free N` for each occupied slot), then:

```bash
clrepo --attach
echo "exit: $?"
```

Expected:
- stderr: `clrepo: no live sessions`
- `exit: 1`
- No tmux attach attempt.

- [ ] **Step 2: Scenario 2 — one live, no worktree**

Start one session in another pane:

```bash
clrepo config    # for example, no -w
# Ctrl-b d to detach
```

Back in the test pane:

```bash
clrepo --attach
```

Expected: tmux attaches immediately to the `config` session. No fzf picker shown. Detach again with `Ctrl-b d`.

- [ ] **Step 3: Scenario 3 — one live with worktree**

Free the previous session (`clrepo --free N`, then `tmux kill-session -t config`). Start a worktree session:

```bash
clrepo config -w doc
# Ctrl-b d to detach
```

Back in the test pane:

```bash
clrepo --attach
```

Expected: auto-attaches to the `config-doc` session (no picker). Detach.

- [ ] **Step 4: Scenario 4 — 2+ live, mixed worktrees**

Start a second session:

```bash
clrepo config             # Ctrl-b d
# (config-doc from Step 3 already running)
```

Back in the test pane:

```bash
clrepo --attach
```

Expected:
- fzf picker opens, header `session>` prompt.
- Two rows, slot-ordered. Each shows `s<n>`, repo (`config`), worktree (`doc` or `—`), age (e.g. `0h02m`).
- Type to fuzzy-filter narrows the list (free fzf behavior).
- `Enter` on a row attaches to that session.
- `Ctrl-C` exits cleanly without attaching (`exit: 130`).

Run twice: once selecting with Enter (verify attach), once cancelling with Ctrl-C (verify exit code).

- [ ] **Step 5: Scenario 5 — one live + one stale slot record**

With the live session from Step 3 still running, manually corrupt `slots.json`:

```bash
cp ~/.cache/clrepo/slots.json /tmp/slots.bak
python3 -c "
import json
p = '/home/freax/.cache/clrepo/slots.json'
with open(p) as f: d = json.load(f)
# Find a free slot
slots = d.setdefault('slots', {})
for n in range(1, 7):
    k = str(n)
    if not slots.get(k):
        slots[k] = {'repo':'ghost','worktree':'','pid':0,
                    'session':'ghost_session_does_not_exist',
                    'started_at': 1000}
        print(f'injected stale into slot {k}'); break
with open(p,'w') as f: json.dump(d, f, indent=2)
"
```

Then:

```bash
clrepo --attach
```

Expected:
- Reconcile prunes the `ghost_session` record (`tmux has-session` fails).
- Picker auto-attaches to the one remaining live session (count is 1 after prune).
- No mention of `ghost` anywhere.

Sanity-check the file was actually pruned:

```bash
grep -c ghost ~/.cache/clrepo/slots.json
```

Expected: `0`.

If the test went sideways, restore: `cp /tmp/slots.bak ~/.cache/clrepo/slots.json`.

- [ ] **Step 6: Scenario 6 — foreground-mode record only**

Free / kill all live tmux sessions first. Then inject a foreground-mode record (no `session` field) using your shell's PID so reconcile keeps it as "alive":

```bash
cp ~/.cache/clrepo/slots.json /tmp/slots.bak
python3 -c "
import json, os
p = '/home/freax/.cache/clrepo/slots.json'
with open(p) as f: d = json.load(f)
slots = d.setdefault('slots', {})
slots['1'] = {'repo':'config','worktree':'','pid': os.getppid(),
              'started_at': 1000}  # NOTE: no 'session' key
with open(p,'w') as f: json.dump(d, f, indent=2)
print('injected foreground-mode record (pid=%d)' % os.getppid())
"

clrepo --attach
echo "exit: $?"
```

Expected:
- stderr: `clrepo: no live sessions`
- `exit: 1`
- The foreground-mode record is filtered out (has no attachable tmux session).

Cleanup:

```bash
cp /tmp/slots.bak ~/.cache/clrepo/slots.json
```

- [ ] **Step 7: Scenario 7 — combo rejection**

Each of these must error out with exit 2 and a message naming the offending flag/positional:

```bash
clrepo -a -w doc;        echo "exit: $?"
clrepo --attach config;  echo "exit: $?"
clrepo -a -r;            echo "exit: $?"
clrepo --attach --no-rc; echo "exit: $?"
clrepo -a --slot 3;      echo "exit: $?"
clrepo -a -p;            echo "exit: $?"
```

Expected for each: stderr message naming the offending flag/positional, `exit: 2`. Sample expected stderr lines:

```
clrepo: --attach takes no other flags (got: -w/--worktree). Run `clrepo <repo>` to launch.
clrepo: --attach takes no positional args (got: config). Run `clrepo <repo>` to launch.
clrepo: --attach takes no other flags (got: -r/--remote/--refresh). Run `clrepo <repo>` to launch.
clrepo: --attach takes no other flags (got: --no-rc). Run `clrepo <repo>` to launch.
clrepo: --attach takes no other flags (got: --slot). Run `clrepo <repo>` to launch.
clrepo: --attach takes no other flags (got: -c/-p). Run `clrepo <repo>` to launch.
```

Sanity-check the silent-`--rc` carveout (intentional per spec):

```bash
clrepo -a --rc; echo "exit: $?"
```

Expected: this is **not** rejected. `--rc` is the default; the parser cannot tell "user typed `--rc`" from "user typed nothing." The picker either runs (picker behavior per scenarios 1/2/4) or errors with `no live sessions`. Either is acceptable; what matters is *not* exit 2 with an `--rc` rejection message.

- [ ] **Step 8: Scenario 8 — detach round-trip**

With at least one live session: `clrepo --attach`, attach, then `Ctrl-b d` to detach. Back at the shell:

```bash
clrepo --status
```

Expected: the slot is still occupied (the table shows the repo/worktree/pid). Detach does not free a slot.

- [ ] **Step 9: Scenario 9 — tab completion**

In an interactive bash shell:

```bash
clrepo --at<TAB>
```

Expected: completes to `clrepo --attach `.

```bash
clrepo -<TAB><TAB>
```

Expected: the displayed flag list includes `-a` and `--attach` alongside the others.

- [ ] **Step 10: Scenario 10 — help text**

```bash
clrepo --help | grep -E '^[[:space:]]+-a, --attach'
```

Expected: one line, e.g. `  -a, --attach          fzf picker over live sessions; reattach to selection`.

- [ ] **Step 11: Final restore check**

Confirm no test residue is left in `slots.json`:

```bash
diff /tmp/slots.bak ~/.cache/clrepo/slots.json && echo "MATCH" || echo "DIFFERENT — investigate"
```

Expected: either `MATCH` (you restored cleanly) or a diff that reflects only legitimate slot state changes from your own session activity, not the `ghost`/foreground fixtures from Steps 5/6. Then:

```bash
rm -f /tmp/slots.bak
```

---

### Task 6: Commit

**Files:**
- `shell/clrepo.sh` (all changes from Tasks 1–4)

- [ ] **Step 1: Verify diff is clean**

```bash
git -C ~/projects/repos/github/freaxnx01/public/config diff shell/clrepo.sh
```

Expected sections, in roughly this order:
1. Version bump on line 25 (`1.15.0` → `1.16.0`).
2. New `_clrepo_reconcile_slots` function inserted above `_clrepo_slot_status`.
3. The reconcile python block removed from `_clrepo_slot_status`, replaced by a `_clrepo_reconcile_slots` call.
4. New `_clrepo_attach_pick` function inserted between `_clrepo_slot_status` and `_clrepo_print_last`.
5. `mode_attach=0` added to the locals on line 1458.
6. New `-a|--attach` case in the parser loop.
7. New combo-rejection + dispatch block after `set -- "${pos[@]}"`.
8. New `-a, --attach` help-text line in the heredoc.
9. `-a --attach` added to the tab-completion `flags=` string.

No unrelated edits. If anything else shows up, stop and reconcile.

- [ ] **Step 2: Stage and commit**

```bash
cd ~/projects/repos/github/freaxnx01/public/config
git add shell/clrepo.sh
git commit -m "$(cat <<'EOF'
feat(clrepo): --attach session picker (closes #18)

Add `clrepo -a|--attach` — fzf picker over live, tmux-backed sessions
that reattaches to the selection. Single live session auto-attaches
(no picker). Standalone flag: combining with any other flag or
positional arg errors with exit 2 and names the offender.

Also extracts the dead-slot reconcile from _clrepo_slot_status into a
new _clrepo_reconcile_slots helper shared by --status and --attach.

Bumps _CLREPO_VERSION 1.15.0 -> 1.16.0.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 3: Confirm**

```bash
git log -1 --stat
```

Expected: one commit, one file changed (`shell/clrepo.sh`), insertions/deletions reflecting the new function + parser changes + version bump.

---

## Self-review (already performed)

**Spec coverage:**
- CLI surface (`-a|--attach`, standalone) → Task 3 Steps 2–3.
- `_clrepo_attach_pick` (reconcile, read & filter, TSV emit, count-branch, attach) → Task 2 Step 1.
- fzf invocation (height/reverse/prompt, trailing-tab session, no `--expect`, no `exec`) → Task 2 Step 1 (the `else` branch in the count-branch).
- `_clrepo_reconcile_slots` extraction with byte-identical `--status` → Task 1 Steps 2–3, verified by Task 1 Step 5 diff.
- Combo-rejection helper (all 8 flag checks + positional check) → Task 3 Step 3.
- Help text line → Task 3 Step 4.
- Tab completion → Task 3 Step 5.
- Edge case 1 (`slots.json` missing/unreadable) → covered by `2>/dev/null` in `_clrepo_attach_pick`'s python; verified implicitly by Scenario 1.
- Edge case 2 (all-foreground-mode) → explicit filter in python (`if not sess: continue`); Scenario 6.
- Edge case 3 (stale slot pruned) → Scenario 5.
- Edge case 4 (Ctrl-C) → `|| return` after fzf; Scenario 4 (second run).
- Edge case 5 (no tmux) → not pre-checked, matches rest of file. Documented in spec.
- Edge case 6 (race) → `tmux attach-session` exits non-zero; user sees tmux's error. Acceptable per spec.
- Edge case 7 (one live → auto-attach) → Scenarios 2, 3, 5.
- Verification matrix (10 rows) → Task 5 Steps 1–10.

**Placeholder scan:** no TBD/TODO; every code step shows complete code; every command shows expected output. The "Setting up the test fixtures" preamble in Task 5 is descriptive prose, not a hidden step.

**Type/name consistency:** `_clrepo_attach_pick`, `_clrepo_reconcile_slots`, `_clrepo_slot_status`, `_clrepo_slots_init`, `_CLREPO_SLOTS_FILE`, `_CLREPO_MAX_SLOTS`, `_CLREPO_FORCED_SLOT`, `_CLREPO_NO_CHANNEL`, `_CLREPO_NO_SYNC`, `mode_attach`, `mode_delete`, `with_remote`, `worktree`, `editor`, `remote_control` all match identifiers already in `shell/clrepo.sh` (verified by grep).
