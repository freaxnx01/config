# clrepo session picker (`--attach`) — design

**Date:** 2026-05-04
**Component:** `shell/clrepo.sh` — new function `_clrepo_attach_pick`, refactor of `_clrepo_slot_status` reconcile step
**Issue:** [#18](https://github.com/freaxnx01/config/issues/18)

## Problem

To reattach to a running Claude Code session today, the user types the repo name (and worktree, if any): `clrepo <repo> [-w <wt>]`. The reattach detection at `shell/clrepo.sh:1313` does the right thing once the args land. The friction is that the user has to remember which slot is running which repo — `clrepo --status` already shows the answer in a table — and then retype it.

When two or more sessions are live, copy-pasting the right line out of `--status` is slower than picking from a list.

## Goal

Add a flag that opens an fzf picker over the live sessions surfaced by `--status` and reattaches to whatever the user selects. Zero typing of repo or worktree names.

## Non-goals

- **No launch path.** Free slots are not picker targets; for new sessions the existing repo picker / positional argument is correct.
- **No combining with launch flags.** `-w`, `-r`, `-c`, `-p`, `--rc`, `--slot`, `--no-channel`, `--no-sync` are all about how to *launch* and don't apply once a session is already running.
- **No pre-filtering by repo.** `clrepo --attach <repo>` is rejected. The picker is small (≤ 6 rows by default) and fzf does live fuzzy filtering for free.
- **No new state.** The picker reads the same `slots.json` that `--status` does. No MRU-of-attaches, no separate cache.
- **No copilot/VS Code support.** Copilot mode skips slot recording (`shell/clrepo.sh:1253-1275`); VS Code skips tmux entirely (`shell/clrepo.sh:1244-1248`). Neither produces an attachable tmux session backed by a slot record.
- **No remote-control composability.** Whether `--rc` was passed at launch is baked into the running session; reattaching cannot change it. Defer any `--attach --rc` interaction until issue #9 (`--status-rc`) lands and clarifies the surface.

## Design

### CLI surface

New flag, parsed in `clrepo()` next to `--status` and `--free`:

```
-a|--attach     fzf picker over live sessions (--status rows); reattach to selection
```

Help text gets one line under the slot-management group in the heredoc at `shell/clrepo.sh:1484-1520`. Tab-completion gets `--attach` and `-a` added to the flags list at `shell/clrepo.sh:1698`.

`--attach` is **standalone**: combining it with any other flag or positional arg is a hard error returning exit code 2. The error names which flag was offending so the user learns the constraint:

```
$ clrepo --attach -w doc
clrepo: --attach takes no other flags (got: -w). Run `clrepo <repo> -w <wt>` to launch.

$ clrepo --attach config
clrepo: --attach takes no positional args. Run `clrepo <repo>` to launch.
```

### Function: `_clrepo_attach_pick`

Lives next to `_clrepo_slot_status` in the slot-helpers block (around `shell/clrepo.sh:1080-1150`). Does five things:

1. **Reconcile.** Calls `_clrepo_reconcile_slots` (extracted from `_clrepo_slot_status`, see below) so dead slots are pruned from `slots.json` before reading.

2. **Read & filter.** Inline Python reads `slots.json`, keeps entries where the slot value is non-null *and* `v.get('session')` is non-empty. Foreground-mode records (no `session` field) are excluded — they are not attachable via tmux.

3. **Emit TSV rows** — one per live slot, in slot order:
   ```
   <slot>\t<repo>\t<worktree-or-empty>\t<age-string>\t<session>
   ```
   Age string formatted as `{h}h{m:02d}m` (without the `ago` suffix `--status` uses — picker rows are tighter than the table).

4. **Count-branch:**

   | Live count | Action |
   |---|---|
   | 0 | `echo "clrepo: no live sessions" >&2; return 1` |
   | 1 | Read the single row, extract `<session>`, attach directly. No picker. |
   | 2+ | Pipe rows through fzf, extract `<session>` from selection, attach. |

5. **Attach.** `tmux attach-session -t "$session"`. No `_clrepo_print_last`, no slot allocation, no telegram setup. Pure attach.

### fzf invocation (2+ live)

```bash
out=$(printf '%s\n' "$rows" \
  | awk -F'\t' '{ printf "s%-3s %-30s %-10s %-12s\t%s\n", \
                  $1, $2, ($3==""?"—":$3), $4, $5 }' \
  | fzf --height=40% --reverse --prompt='session> ' \
        -d $'\t' --with-nth=1) || return
session=$(printf '%s' "$out" | awk -F'\t' '{print $2}')
[ -z "$session" ] && return
tmux attach-session -t "$session"
```

Key choices:

- **Trailing tab-separated session name** with `-d $'\t' --with-nth=1` — display column is human-formatted, but the exact session name stays attached for unambiguous extraction. Same trick used by the existing meta-search picker at `shell/clrepo.sh:1635-1638`.
- **`--height=40% --reverse --prompt=`** — matches existing fzf usage across clrepo (`shell/clrepo.sh:1637, 1671`).
- **No `--expect` keys** — the picker has one job. Enter selects, Ctrl-C cancels. No Ctrl-D / Ctrl-N / Ctrl-R.
- **No `exec`** — plain call to `tmux attach-session`. Matches the rest of the file; the micro-saving from `exec` isn't worth the inconsistency.

### Refactor: `_clrepo_reconcile_slots`

The dead-slot reconciliation block currently inlined in `_clrepo_slot_status` at `shell/clrepo.sh:1087-1115` (tmux-has-session check, PID-liveness fallback, key pruning) is extracted into its own function. `_clrepo_slot_status` calls it; `_clrepo_attach_pick` calls it. Behavior is unchanged — the block is idempotent and silent on no-op.

The existing `2>/dev/null` wrapping is preserved: any Python exception swallows silently and leaves `slots.json` untouched. Both callers tolerate stale data better than they tolerate noise on stderr.

### Combo-rejection helper

A small helper validates the parser-collected flag/positional state before dispatching to `_clrepo_attach_pick`. Implemented as a check in `clrepo()` *after* the parser loop, so it sees flags that follow `--attach` on the command line:

```bash
# Inside clrepo(), after the case-loop and `set -- "${pos[@]}"`:
if [ "$mode_attach" = 1 ]; then
  local bad=""
  [ "$with_remote" = 1 ]            && bad="${bad:+$bad, }-r/--remote/--refresh"
  [ "$mode_delete" = 1 ]            && bad="${bad:+$bad, }-D/--delete"
  [ -n "$worktree" ]                && bad="${bad:+$bad, }-w/--worktree"
  [ -n "$editor" ]                  && bad="${bad:+$bad, }-c/-p"
  [ "$_CLREPO_NO_CHANNEL" = 1 ]     && bad="${bad:+$bad, }--no-channel"
  [ "$_CLREPO_NO_SYNC" = 1 ]        && bad="${bad:+$bad, }--no-sync"
  [ -n "$_CLREPO_FORCED_SLOT" ]     && bad="${bad:+$bad, }--slot"
  [ "$remote_control" != 1 ]        && bad="${bad:+$bad, }--rc/--no-rc"
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
```

The `--attach` case in the parser loop just sets `mode_attach=1`. A new `mode_attach` local is added to the existing block at `shell/clrepo.sh:1458`.

The `--rc/--no-rc` check needs care: `remote_control=1` is the *default*, so `[ "$remote_control" != 1 ]` only fires when the user passed `--no-rc`. We can't distinguish "user passed `--rc` (no-op default)" from "user passed nothing" without parser changes — and that's fine. The default case is silent; only an *explicit* `--no-rc` opts in to the rejection.

## Edge cases

| Case | Behavior |
|---|---|
| `slots.json` missing/unreadable | Reconcile no-ops, picker reads no rows, falls through to "no live sessions" path. |
| All slot records foreground-mode (no `session` field) | Filtered at step 2, treated as zero-live. |
| Stale slot record (tmux session gone) | Reconcile clears it before the picker reads. |
| User Ctrl-C's the picker | fzf returns non-zero, `\|\| return` short-circuits, no attach. Standard pattern. |
| `tmux` not installed | `tmux attach-session` fails noisily. No pre-check (rest of the file doesn't pre-check either; if you're hitting `--attach` without tmux you have bigger problems). |
| Race between reconcile and attach (tmux session vanishes in the gap) | `tmux attach-session` exits non-zero; the user sees tmux's error. Acceptable — single-user, very tight window. |
| User has only one live session | Auto-attach, no picker shown. Skipping the one-row picker is the whole point of the feature. |

## Verification (manual)

No automated test suite. Manual matrix to run after implementation:

| # | Scenario | Expected |
|---|---|---|
| 1 | All slots free | `clrepo: no live sessions` on stderr, exit 1 |
| 2 | One live, no worktree | Auto-attach, no picker |
| 3 | One live with worktree | Auto-attach to `<repo>-<wt>` session |
| 4 | 2+ live, mixed worktrees | Picker, slot-ordered rows, Enter attaches, Ctrl-C exits clean |
| 5 | One live + one stale slot record | Reconcile prunes stale, picker auto-attaches the live one |
| 6 | Foreground-mode record only | Filtered out, treated as zero-live |
| 7 | `clrepo -a -w doc` / `clrepo -a config` | Hard error, exit 2 |
| 8 | Detach (`Ctrl-b d`) from attached session | Returns to shell, `--status` still shows slot occupied |
| 9 | `clrepo --at<Tab>`, `clrepo -<Tab>` | Completes `--attach`; `-a` listed |
| 10 | `clrepo --help` | New `-a, --attach` line present |

## Risks

- **Reconcile extraction regression** — the existing block has been stable; extracting it without behavior change should be mechanical, but the spec calls for verifying `--status` output is unchanged before and after.
- **fzf row formatting drift from `--status`** — the column widths are duplicated between the two functions. If `--status` formatting changes later, the picker will look slightly different. Acceptable; both formatters are cosmetic. Not worth a shared formatter today.

## Out of scope (later, if needed)

- **`--attach --rc`** — depends on issue #9.
- **Free-slot launch shortcut** (`--attach --all`) — explicitly rejected; existing repo picker covers launch.
- **MRU-of-attaches ordering** — would require new state. Slot order is good enough for ≤ 6 rows.
- **Shared `_clrepo_slot_rows` producer** consumed by both `--status` and `--attach` — tempting if more callers appear (e.g. issue #9). YAGNI for now.
