# clrepo — Architecture & Editing Guide

## What it is

A bash function that picks a repo under `~/projects/repos/` via fzf and launches Claude Code. Sourced from `~/.bashrc`.

## File locations

| What | Path |
|---|---|
| Source file | `~/projects/repos/github/freaxnx01/public/config/shell/clrepo.sh` |
| Repo | `github.com/freaxnx01/config` (public, branch `main`) |
| bashrc source line | `~/.bashrc` lines 146–149 |
| MRU + remote cache | `~/.cache/clrepo/` |
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
clrepo <name>                   # case-insensitive basename lookup, local-only
clrepo -r                       # picker + streaming remote listings from all forges
clrepo --refresh                # force-refresh remote cache, then pick
clrepo -D <name>                # non-interactive delete (local repos only)
clrepo <name> -w <worktree>     # pass --worktree to claude
clrepo --help                   # usage
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
| `_clrepo_remote_list()` | Union of all targets, cached with 10min TTL, streams via `tee` |
| `_clrepo_clone_url()` | Infer clone URL from rel path (HTTPS for GitHub/GitLab, SSH for Forgejo) |
| `_clrepo_git_clone_in()` | `git clone` with direnv-loaded creds; injects HTTPS credential helper for GitHub |
| `_clrepo_clone_remote()` | Resolve URL + clone + invalidate cache |
| `_clrepo_create_new()` | Forge picker → name prompt → API POST → clone → launch |
| `_clrepo_delete()` | Dirty check → L/R/B prompt → type-to-confirm → API DELETE + rm -rf |
| `_clrepo()` | Tab completion (case-insensitive basenames + flags) |

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
