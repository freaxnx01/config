#!/usr/bin/env bash
# Warn about unpushed commits on clrepo session exit.
#
# Two modes:
#   sourced:   defines _clrepo_warn_unpushed <repo_path>
#   executed:  $1 = tmux session name; reads stored path, shows tmux display-message.
#
# Same sourcing pattern as clrepo-autosync.sh — do NOT enable strict mode at
# file scope (would break the interactive shell that sources clrepo.sh).

_CLREPO_CACHE="${_CLREPO_CACHE:-$HOME/.cache/clrepo}"

_clrepo_warn_unpushed() {
  local repo_path="${1:-$PWD}"
  [ -d "$repo_path" ] || return 0
  git -C "$repo_path" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  local upstream
  upstream=$(git -C "$repo_path" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) \
    || return 0

  local count
  count=$(git -C "$repo_path" rev-list --count "${upstream}..HEAD" 2>/dev/null) || return 0
  [ "${count:-0}" -gt 0 ] || return 0

  local branch repo_name
  branch=$(git -C "$repo_path" symbolic-ref --quiet --short HEAD 2>/dev/null)
  repo_name=$(basename "$repo_path")

  printf '\033[1;33m⚠  clrepo: %d unpushed commit(s) on %s in %s — push before leaving!\033[0m\n' \
    "$count" "$branch" "$repo_name" >&2
}

# Script mode: tmux pane-died hook entry point.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -uo pipefail
  session="${1:-}"
  [ -z "$session" ] && exit 0

  path_file="$_CLREPO_CACHE/sessions/${session}.path"
  [ -f "$path_file" ] || exit 0
  repo_path=$(< "$path_file")

  [ -d "$repo_path" ] || exit 0
  git -C "$repo_path" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

  upstream=$(git -C "$repo_path" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) \
    || exit 0
  count=$(git -C "$repo_path" rev-list --count "${upstream}..HEAD" 2>/dev/null) || exit 0
  [ "${count:-0}" -gt 0 ] || exit 0

  branch=$(git -C "$repo_path" symbolic-ref --quiet --short HEAD 2>/dev/null)
  repo_name=$(basename "$repo_path")

  tmux display-message -t "$session" -d 5000 \
    "⚠  clrepo: ${count} unpushed commit(s) on ${branch} in ${repo_name} — push before leaving!"
fi
