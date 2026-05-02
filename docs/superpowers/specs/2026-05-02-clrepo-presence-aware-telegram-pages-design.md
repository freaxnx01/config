# clrepo presence-aware Telegram pages — design

**Date:** 2026-05-02
**Component:** `shell/clrepo.sh`, new files under `shell/clrepo-hooks/` and `shell/clrepo-watcher.sh`

## Problem

`clrepo` launches each Claude Code slot with `--channels plugin:telegram@...`, exposing a per-slot Telegram bot (`@claude_freax_s<N>_bot`). Today the channel only forwards traffic when the user DMs the bot first — Claude itself never proactively pages Telegram. Two important events therefore stay invisible while the user is away from their PC:

1. **Human-in-the-loop pause** — a long-running task (e.g. a Superpowers `executing-plan` run) is interrupted because Claude needs a decision before continuing.
2. **Usage limit reached** — Claude stops responding because the 5-hour limit has been hit.

In both cases the session sits idle indefinitely until the user notices it on their tmux pane. When the user is away from the PC (e.g. SSH'd in from Win11/WSL2 and now out of the house), this can waste hours of wall-clock time.

Conversely, when the user *is* at the PC, paging Telegram for these events is noisy and unwanted — the terminal already shows them.

## Goal

When the user is **away** from the PC, automatically page their Telegram bot for the two event classes above, with enough metadata + context to reply directly from the chat. When the user is **present**, stay silent.

The reply path is unchanged: each slot's existing per-slot bot already routes inbound DMs back to that slot via the existing `--channels` mechanism.

## Non-goals

- Not a replacement for [Remote Control + mobile push](https://code.claude.com/docs/en/remote-control). The user is enabling that in parallel as a zero-code path; this design exists for finer per-event control and the existing Telegram-bot habit.
- No notification of routine events (assistant turns, tool calls, permission prompts — the latter are bypassed by `--dangerously-skip-permissions`).
- No multi-user / group routing. Pages go to the slot's existing allowlisted DM (`telegram_user_id` from `~/.cache/clrepo/owner.json`).
- No persistence of pages across reboots. The presence file persists; in-flight idle markers do not.
- No cross-machine presence. Single-host (claude-dev) only.
- No retry / queueing on Telegram API failure. Page is best-effort.

## Definitions

- **Slot** — one of `s1..s6`, each backed by `~/.claude-s<N>` (`CLAUDE_CONFIG_DIR`) and a tmux session named after the repo (+ optional worktree).
- **Present** — for slot `s<N>`, its tmux session has ≥1 attached client (`tmux list-clients -t <session>`).
- **Away** — for slot `s<N>`, its tmux session has 0 attached clients.
- **Manual override** — a global state in `~/.cache/clrepo/presence` that can force away/present regardless of tmux state.

## Presence model

Per-slot tmux check + global manual override.

| `~/.cache/clrepo/presence` | Effective state for slot `s<N>` |
|---|---|
| missing or `auto` | `present` if the slot's tmux session has ≥1 client, else `away` |
| `away` | `away` (regardless of tmux) |
| `here` | `present` (regardless of tmux) |

The file persists across reboots. Default = `auto`.

### CLI surface

Three new sub-commands on the existing `clrepo` function:

| Command | Effect |
|---|---|
| `clrepo away` | write `away` to the presence file; print one-line confirmation incl. the slots currently affected |
| `clrepo back` | write `auto` to the presence file (resume per-slot tmux detection); confirm |
| `clrepo here` | write `here` to the presence file; confirm |

A fourth helper for visibility:

| Command | Effect |
|---|---|
| `clrepo presence` | print current mode + per-slot effective state |

These are dispatched in the main `clrepo()` arg parser, parallel to `--status` and `update`.

## Event sources

Two distinct event sources, two generators.

### Generator A — Notification hook (HITL)

Each slot's `~/.claude-s<N>/settings.json` registers two hooks pointing at shared scripts in `shell/clrepo-hooks/`:

- `Notification` → `notify.sh`
- `UserPromptSubmit` → `clear-idle.sh`

The hook scripts are repo-tracked; clrepo materializes the settings.json fragment via a new `_clrepo_install_hooks <slot>` function called from `_clrepo_slot_allocate` (idempotent — only writes if missing or stale).

#### `notify.sh` (Notification hook)

Receives the standard hook JSON on stdin. Acts only on these event types:

| `notification_type` | Action |
|---|---|
| `idle_prompt` | Touch `~/.cache/clrepo/sessions/<slot>.idle-since`, then `(sleep 120 && check_and_page) &disown`. The delayed check re-reads the file: if it still exists and its mtime is ≥ 120s old, send a page; otherwise silently exit. |
| `elicitation_dialog` | Send a page immediately (no debounce — these are explicit MCP-driven prompts and rare). |
| any other type (`auth_success`, `permission_prompt`, `elicitation_complete`, `elicitation_response`) | Ignore. |

The 120s debounce avoids paging for trivial pauses (sub-2-min thinking gaps). It is implemented as a detached subshell so the hook returns immediately and never blocks Claude.

#### `clear-idle.sh` (UserPromptSubmit hook)

Removes `~/.cache/clrepo/sessions/<slot>.idle-since` if it exists. Runs every time the user submits input, ensuring a debounced page that hasn't fired yet is cancelled (the delayed `check_and_page` finds the marker missing and exits).

### Generator B — Usage-limit watcher

A single global daemon, `shell/clrepo-watcher.sh`, polls each active slot's tmux pane every 30s for the literal usage-limit phrase ("limit reached" or the specific Claude Code wording — to be confirmed at implementation time by triggering one).

Lifecycle:

- Started by `_clrepo_slot_allocate` *if not already running* (PID file at `~/.cache/clrepo/watcher.pid`, liveness check via `kill -0`). Idempotent.
- Loops: read `~/.cache/clrepo/slots.json`, for each occupied slot capture its tmux pane, grep for the limit phrase. If matched and not already paged in this session (idempotency tracked in `~/.cache/clrepo/sessions/<slot>.limit-paged`), send a page.
- Self-exits when `slots.json` reports zero occupied slots for two consecutive polls (60s grace).

The 30s poll cadence is a compromise: faster wastes CPU, slower delays the page. Acceptable because hitting the limit is itself a slow event.

## Page format

Single message per event. Format:

```
🤔 [s4/repo-name worktree:fix-bug branch:main]
Claude is waiting for input (idle 3m)

Last:
> <up to ~500 chars of stripped tmux pane tail>
```

For usage limit:

```
🛑 [s4/repo-name worktree:fix-bug branch:main]
Usage limit reached

Last:
> <pane snippet>
```

The `Last:` snippet is captured at page time via `tmux capture-pane -p -t <session>`, then run through `sed 's/\x1b\[[0-9;]*[mGKH]//g'` to strip ANSI escapes, take the trailing non-blank lines up to 500 chars total. Best-effort — the rendered TUI may produce ugly output for some events; that is acceptable for a page meant to nudge the user, not to be the canonical record.

Sent via the existing per-slot bot (`$_SLOT_TOKEN`) to `telegram_user_id` from `~/.cache/clrepo/owner.json` — same path `_clrepo_telegram_setup` already uses.

## Gate

Both generators consult `_clrepo_should_page <slot>` before sending. The function returns 0 (page) when:

```
read presence_mode from ~/.cache/clrepo/presence (default: "auto")
case "$presence_mode" in
  away) return 0 ;;                                    # always page
  here) return 1 ;;                                    # never page
  auto) tmux list-clients -t <slot's session> | wc -l == 0 ;;  # away iff no clients
esac
```

Per-slot resolution happens because the function is called with the slot number; the tmux session name is read from `~/.cache/clrepo/slots.json` (the `session` field already recorded by `_clrepo_slot_record`).

## File layout

| Path | Purpose |
|---|---|
| `shell/clrepo.sh` | New: `_clrepo_install_hooks`, `_clrepo_should_page`, `_clrepo_telegram_page`, `_clrepo_presence_set`, `_clrepo_presence_show`. Three new sub-commands wired into the arg parser. Watcher start in `_clrepo_slot_allocate`. |
| `shell/clrepo-hooks/notify.sh` | New. Notification hook. |
| `shell/clrepo-hooks/clear-idle.sh` | New. UserPromptSubmit hook. |
| `shell/clrepo-watcher.sh` | New. Usage-limit watcher daemon. |
| `~/.cache/clrepo/presence` | New runtime state. One line: `auto` / `away` / `here`. |
| `~/.cache/clrepo/sessions/<slot>.idle-since` | New runtime marker. Touched on idle_prompt, deleted on UserPromptSubmit. |
| `~/.cache/clrepo/sessions/<slot>.limit-paged` | New runtime marker. Set by watcher to deduplicate within a session. Cleared on slot free. |
| `~/.cache/clrepo/watcher.pid` | New. PID file for the watcher daemon. |
| `~/.cache/clrepo/watcher.log` | New. Watcher daemon log (rotated by size, max 1MB). |
| `~/.cache/clrepo/hooks.log` | New. Notification/UserPromptSubmit hook log for debugging payload schemas (rotated by size, max 1MB). |
| `~/.cache/clrepo/hooks.lock` | New. Advisory lock for `_clrepo_install_hooks` settings.json merges. |
| `~/.claude-s<N>/settings.json` | Modified per-slot. Adds `Notification` + `UserPromptSubmit` hook entries pointing at the shared scripts. |

## Hook installation

`_clrepo_install_hooks <slot>` reads the slot's `settings.json` (creating an empty `{}` if absent), merges in the two hook entries (idempotent — checks if the same `command` is already registered), and writes back. Uses `python3 -c` for JSON merge; the rest of clrepo already does this.

The shared script paths are absolute, derived from `$_CLREPO_DIR` (the directory clrepo.sh sources from). Both scripts must be `chmod +x` — checked by clrepo at install time, fixed if needed.

## Integration with existing flows

- **Slot allocation** (`_clrepo_slot_allocate`): after the existing token loading, call `_clrepo_install_hooks "$_SLOT"` and start the watcher if not running. Both idempotent.
- **Slot free** (`_clrepo_slot_free`): clear `<slot>.idle-since` and `<slot>.limit-paged` markers. The watcher's self-exit path handles its own teardown.
- **Telegram setup/cleanup** (`_clrepo_telegram_setup` / `_clrepo_telegram_cleanup`): unchanged. The new pages go through a parallel `_clrepo_telegram_page` helper that shares the bot token and owner-id lookup but sends arbitrary text.

## Help text additions

```
  away                  set presence to "away" (Telegram pages enabled for all slots)
  back                  resume auto-detection (per-slot tmux client check)
  here                  set presence to "here" (Telegram pages disabled for all slots)
  presence              show current presence mode and per-slot effective state
```

## Tab completion

Add `away`, `back`, `here`, `presence` to the sub-command list in `_clrepo`.

## Coexistence with Remote Control + mobile push

The user enables Anthropic's official Remote Control + mobile push in `/config` as a parallel notification surface. Remote Control's mobile push fires when Claude itself decides ("long-running task finishes" / "needs a decision"). This design adds Telegram pages with explicit per-event rules and a presence gate.

Both can fire for the same event. The user can mute either side independently (presence file for Telegram; OS-level Focus mode for the Claude app). No code interaction between the two.

## Edge cases

| Case | Behavior |
|---|---|
| Slot reattached via `tmux attach-session` after a debounced page already fired | The page is in Telegram history; user sees it on next reattach. No retraction. |
| User attaches to slot's tmux WHILE the 120s timer is pending | The delayed `check_and_page` re-runs the gate (`_clrepo_should_page`) right before sending. Attaching mid-debounce flips the gate to "present" → no page. (This re-check is mandatory, not optional — listed in `notify.sh`'s contract.) |
| Multiple `idle_prompt` events fire within 120s | Each fires a detached subshell. Worst-case: duplicate pages. Not deduplicated because in practice `idle_prompt` does not fire repeatedly within 2 min — Claude is either idle (no new event) or active (idle marker cleared). If observed in the wild, add a `<slot>.idle-paged` marker as a follow-up. |
| `presence` file contains an unrecognized value | Treat as `auto` (safe default). |
| Watcher dies (crash, OOM) | Next slot allocation restarts it via the PID-file liveness check. |
| Two clrepo invocations race on `_clrepo_install_hooks` | Settings.json merge uses the existing `flock`-style pattern from `_clrepo_slot_record`. (To be added — currently the existing helpers don't lock settings.json. New lock at `~/.cache/clrepo/hooks.lock`.) |
| User sets presence to `away` while at the PC for testing | Works as documented. The `clrepo presence` output shows `mode=away` so the user can tell. |

## Out of scope (explicit)

- No web UI / status page for presence.
- No per-slot manual override (only global).
- No replacement of `_clrepo_telegram_setup` / `_clrepo_telegram_cleanup` banners — those continue to fire on session start/end as before.
- No bidirectional ack ("user replied via Telegram → mark idle marker handled"). The reply lands in Claude's input via the existing channel; the next `UserPromptSubmit` from that input clears the marker. So this is implicitly handled, not explicitly designed.

## Open questions

1. **Exact usage-limit string.** The watcher's grep pattern depends on the literal text Claude Code prints when the 5h limit is hit. Confirmed at implementation time by triggering one (or by checking Claude Code source). Until confirmed, the watcher logs all candidate matches to `~/.cache/clrepo/watcher.log` for tuning.
2. **Hook payload schema for `idle_prompt`.** Docs confirm the event name but not the JSON field that exposes idle-duration. If duration is in the payload, the 120s debounce can be inlined (no marker file needed). To be checked on first `notify.sh` test fire (script logs the raw payload to `hooks.log` until confirmed).

Both are non-blocking — the design works with the conservative "scrape pane / use marker file" approach in either case; the open questions are optimizations.
