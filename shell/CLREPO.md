# clrepo — Architecture & Editing Guide

## What it is

A bash function that picks a repo under `~/projects/repos/` via fzf and launches Claude Code. Sourced from `~/.bashrc`.

## File locations

| What | Path |
|---|---|
| Source file | `~/projects/repos/github/freaxnx01/public/config/shell/clrepo.sh` |
| Repo | `github.com/freaxnx01/config` (public, branch `main`) |
| bashrc source line | `~/.bashrc` lines 146–149 |
| MRU + remote cache + metadata cache | `~/.cache/clrepo/` (`mru`, `remote.list`, `repo-meta.json`) |
| Forgejo `.envrc` | `~/projects/repos/git-forgejo/.envrc` (not in a git repo, local-only artifact) |

## Repo tree layout

```
~/projects/repos/
├── github/<owner>/(public|private)/<repo>/   ← each public/private dir has .envrc loading GH_TOKEN from Passbolt
├── gitlab/<owner>/<repo>/                    ← .envrc at gitlab/<owner>/ loads GITLAB_TOKEN
└── git-forgejo/<repo>/                       ← .envrc at git-forgejo/ loads FORGEJO_TOKEN
```

## Discovery model

Every `.envrc` under `~/projects/repos/` whose path matches the layout is a **forge target**: a credential source + clone destination. Target metadata (forge type, owner, visibility) is inferred from the path pattern — no sidecar config files.

| Path pattern | Forge | Owner | Visibility |
|---|---|---|---|
| `github/<owner>/public` | github | `<owner>` | public |
| `github/<owner>/private` | github | `<owner>` | private |
| `gitlab/<owner>` | gitlab | `<owner>` | — |
| `git-forgejo` | forgejo | `freax` (hardcoded) | — |

Adding a new forge target = create the directory + `.envrc` that loads the right token.

## CLI surface

```
clrepo                          # fzf picker (local, fast, MRU on top)
clrepo <name>                   # case-insensitive basename lookup; on miss, falls back to topic/description search
clrepo -r                       # picker + streaming remote listings from all forges
clrepo --refresh                # force-refresh remote cache, then pick
clrepo -D <name>                # non-interactive delete (local repos only)
clrepo <name> -w <worktree>     # pass --worktree to claude
clrepo <name> --remote-control  # pass --remote-control to claude (alias --rc)
clrepo --help                   # usage
clrepo away                     # presence: force "away" (enable Telegram pages for all slots)
clrepo back                     # presence: resume auto-detection (per-slot tmux client check)
clrepo here                     # presence: force "here" (suppress Telegram pages for all slots)
clrepo presence                 # show current presence mode + per-slot effective state
```

## Picker keybindings

| Key | Action |
|---|---|
| Enter | Launch (clone first if `↓` remote entry) |
| Ctrl-N | Create new remote repo (fzf query = seed name) → forge picker → name prompt → API POST → clone → launch |
| Ctrl-D | Delete highlighted repo (prompts L/R/B/cancel, type-to-confirm for remote) |
| Ctrl-R | Refresh remote cache (only in `-r` mode) |

## Function map

| Function | Purpose |
|---|---|
| `clrepo()` | Main entry: flag parsing, picker, dispatch |
| `_clrepo_launch()` | **Single launch point.** cd, update MRU, tmux wrap if SSH, then `claude`. The slot/telegram wrapper replaces this body. |
| `_clrepo_targets()` | Walk `.envrc` tree → emit TSV of forge targets |
| `_clrepo_fetch_target()` | One forge API call in a direnv-activated subshell |
| `_clrepo_remote_list()` | Union of all targets, cached with 10min TTL, streams via `tee`; also persists `repo-meta.json` (description + topics per repo) |
| `_clrepo_meta_search()` | Case-insensitive keyword match against cached topics + description; emits `<type>\t<path>\t<snippet>` TSV |
| `_clrepo_clone_url()` | Infer clone URL from rel path (HTTPS for GitHub/GitLab, SSH for Forgejo) |
| `_clrepo_git_clone_in()` | `git clone` with direnv-loaded creds; injects HTTPS credential helper for GitHub |
| `_clrepo_clone_remote()` | Resolve URL + clone + invalidate cache |
| `_clrepo_create_new()` | Forge picker → name prompt → API POST → clone → launch |
| `_clrepo_delete()` | Dirty check → L/R/B prompt → type-to-confirm → API DELETE + rm -rf |
| `_clrepo()` | Tab completion (case-insensitive basenames + flags) |

## Keyword lookup (metadata fallback)

If `clrepo <name>` doesn't match any local repo basename, it falls back to searching **topics and description** across the cached forge metadata (`~/.cache/clrepo/repo-meta.json`).

- **Populated by** any run that reaches `_clrepo_remote_list` (i.e. `clrepo -r` or `clrepo --refresh`). Cache TTL applies; re-fetched together with `remote.list`.
- **Match order:** topic hits rank above description hits. Within each group, sorted by repo basename.
- **1 hit** → auto-launch. If the hit is an uncloned remote repo, clones first (same flow as picker).
- **2+ hits** → fzf picker annotated with `<path>  [topic: <match>]` or `<path>  [desc: …snippet…]`.
- **0 hits** → `clrepo: no such repo: <name>` (exit 1), same as before.

To make a repo keyword-reachable, tag it on the forge:

```bash
gh repo edit <owner>/<repo> --add-topic <keyword>      # GitHub
```

GitLab and Forgejo also expose topics in their repo settings; topics and description are pulled from whichever API the `.envrc` target hits.

## Credential flow

All forge API calls (list, create, delete, clone-auth) use **per-dir PATs loaded via direnv**:

1. Subshell `cd` into the target's `.envrc` directory
2. `eval "$(direnv export bash)"` — this runs the `.envrc` which loads the token from Passbolt
3. Use the exported `GH_TOKEN` / `GITLAB_TOKEN` / `FORGEJO_TOKEN` for curl/git

GitHub clone uses an inline `credential.helper` injected via `git -c` (no SSH key for GitHub).
Forgejo clone uses SSH on port 222 (`~/.ssh/id_ed25519_forgejo`).
GitLab clone uses HTTPS via the `GIT_CONFIG_*` credential helper wired in its `.envrc`.

GitHub delete requires `delete_repo` scope on the per-dir PAT (edit at https://github.com/settings/tokens, same token string).

## SSH persistence (tmux)

When `$SSH_CONNECTION` is set, `_clrepo_launch` wraps claude in:
```bash
tmux new-session -A -s "<repo>[-<worktree>]" claude -n <repo> [--worktree <wt>]
```
`-A` = attach-or-create. Disconnecting the SSH client detaches tmux; re-running the same `clrepo` command reattaches.

Session name = repo basename (+ `-<worktree>` if specified), sanitized to `[A-Za-z0-9_-]`.

## Integration point for slot/telegram

The slot/telegram spec (separate document) replaces `_clrepo_launch()` to add:
- Slot allocation (N parallel sessions with pid tracking)
- Per-slot `CLAUDE_CONFIG_DIR` (`~/.claude-sN`)
- Telegram bot naming + banner message + pin
- Exit hooks for cleanup

Everything upstream of `_clrepo_launch` (picker, clone, create, delete, MRU, worktree parsing) is untouched. The worktree name arrives as `$2` of `_clrepo_launch`.

## Presence-aware Telegram pages

clrepo proactively pages each slot's Telegram bot when Claude is paused or
hits the 5h usage limit, but only when the user is **away** from the slot's
tmux session. See spec at `docs/superpowers/specs/2026-05-02-clrepo-presence-aware-telegram-pages-design.md`.

### Presence model

| `~/.cache/clrepo/presence` | Effective state |
|---|---|
| missing or `auto` | per-slot: present iff the slot's tmux session has ≥1 attached client |
| `away` | always away (forced — pages always sent) |
| `here` | always present (forced — pages suppressed) |

### Event sources

- **Notification hook** (per-slot `~/.claude-s<N>/settings.json`): `idle_prompt` (debounced 120s) and `elicitation_dialog` (immediate) trigger a page via `shell/clrepo-hooks/notify.sh`. `UserPromptSubmit` fires `shell/clrepo-hooks/clear-idle.sh` to cancel a pending idle page.
- **Watcher daemon** (`shell/clrepo-watcher.sh`): polls every 30s for the usage-limit phrase in each active slot's tmux pane. Started by `_clrepo_slot_allocate`, self-exits when no slots are occupied.

Both event sources gate through `_clrepo_should_page` before sending. Pages go to the slot's existing per-slot bot (`@claude_freax_s<N>_bot`); replies route back via the existing `--channels plugin:telegram@...` mechanism.

## Use cases: Telegram pages vs. Remote Control

Two independent channels keep you in the loop when away from the terminal. Both are on by default; opt out with `--no-channel` (Telegram + slot tracking) or `--no-remote-control` / `--no-rc`.

| | Telegram pages | Remote Control |
|---|---|---|
| Direction | push (Claude → you) | pull (you → Claude) |
| Triggers | idle prompt (debounced 120s), elicitation dialog, 5h usage limit | manual — open claude.ai/code or mobile app |
| Granularity | discrete pages with short replies | full live-session steering (read + write) |
| Auth | per-slot bot token (Passbolt-backed) | claude.ai OAuth |
| Context cost | zero — pages are out-of-band | counts against the live session's usage quota |
| Presence-aware | yes — gated on `~/.cache/clrepo/presence` | no — always available while session is alive |

### Telegram — when to use

- **Long-running tasks.** Kick off, walk away, get pinged when Claude pauses or hits the 5h limit.
- **Many parallel slots.** Each slot has its own bot, so the page identifies *which* session needs attention.
- **One-line replies suffice.** "yes", "go ahead", "use option 2" — no need to open a full client.

### Remote Control — when to use

- **Steer from anywhere.** Continue an active session from claude.ai/code or the mobile app without an SSH terminal.
- **Spectate long runs.** Watch context unfold in the browser without holding the tmux attach.
- **Device hand-off.** Start at desk, continue on laptop or phone — same live session.

### Combining them — meaningful?

Yes. Treat them as complementary tiers, not redundant:

1. **Telegram** pages you when something needs attention (push, low-friction, free).
2. If a one-line reply suffices, answer in Telegram — done.
3. If you need full context — read scrollback, send a multi-line steer, kick off a follow-up — open **Remote Control** on the same session.

Both target the same underlying Claude session, so a Telegram reply and a Remote Control prompt land in the same conversation. Presence governs Telegram alone; Remote Control is always reachable while the session is alive.

## Config variables

| Variable | Default | Purpose |
|---|---|---|
| `_CLREPO_BASE` | `/home/freax/projects/repos` | Root of the repo tree |
| `_CLREPO_CACHE` | `~/.cache/clrepo` | MRU, remote cache, (future: slots) |
| `_CLREPO_REMOTE_TTL` | `600` (10 min) | Remote listing cache lifetime in seconds |

## Known limitations

- GitHub API `per_page=100`: owners with 100+ repos in a single visibility will be truncated. Fix: add pagination.
- Forgejo owner is hardcoded to `freax` in the path-inference table.
- `clrepo -D <name>` only matches local repos. Use picker Ctrl-D for uncloned remote-only repos.
- No parallel forge API calls: each target is fetched sequentially. With 5 targets, worst case is ~2.5s (cache miss).
