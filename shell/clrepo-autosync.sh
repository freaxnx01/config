#!/usr/bin/env bash
# clrepo autosync — best-effort commit & push on session close.
# Opt-in via `export CLREPO_AUTOSYNC=1` in the repo's .envrc.
# Never fails the caller; every error path returns 0.
#
# Two modes:
#   sourced:   defines _clrepo_autosync <repo_path> [token]
#   executed:  $1 = tmux session name, $2 = optional bot token.
#              Reads repo path from $_CLREPO_CACHE/sessions/<session>.path

set -uo pipefail

_CLREPO_CACHE="${_CLREPO_CACHE:-$HOME/.cache/clrepo}"
_CLREPO_OWNER="$_CLREPO_CACHE/owner.json"

_autosync_warn() {
  printf '\033[33mclrepo: autosync %s\033[0m\n' "$*" >&2
}

_autosync_ok() {
  printf '\033[32mclrepo: autosync %s\033[0m\n' "$*" >&2
}

_autosync_telegram() {
  local token="$1" text="$2"
  [ -z "$token" ] && return 0
  [ -f "$_CLREPO_OWNER" ] || return 0
  local owner_id
  owner_id=$(python3 -c "
import json
try:
    with open('$_CLREPO_OWNER') as f: d = json.load(f)
    print(d.get('telegram_user_id', ''))
except Exception:
    pass
" 2>/dev/null)
  [ -z "$owner_id" ] && return 0
  curl -sf -X POST "https://api.telegram.org/bot${token}/sendMessage" \
    -H "Content-Type: application/json" \
    -d "$(python3 -c "import json,sys; print(json.dumps({'chat_id':'$owner_id','text':'''$text'''}))" 2>/dev/null)" \
    >/dev/null 2>&1 || true
}

_clrepo_autosync() {
  local repo_path="$1" token="${2:-}"
  [ -z "$repo_path" ] && return 0
  [ -d "$repo_path" ] || return 0

  cd "$repo_path" 2>/dev/null || return 0

  # Load .envrc to discover CLREPO_AUTOSYNC opt-in.
  if command -v direnv >/dev/null 2>&1; then
    eval "$(direnv export bash 2>/dev/null)" || true
  fi
  [ "${CLREPO_AUTOSYNC:-0}" = 1 ] || return 0

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  local repo_name branch upstream
  repo_name=$(basename "$repo_path")
  branch=$(git symbolic-ref --quiet --short HEAD) || {
    _autosync_warn "skip ($repo_name): detached HEAD"; return 0; }
  upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) || {
    _autosync_warn "skip ($repo_name): no upstream for $branch"; return 0; }

  case "$branch" in
    main|master)
      [ "${CLREPO_AUTOSYNC_ALLOW_MAIN:-0}" = 1 ] || {
        _autosync_warn "skip ($repo_name): branch '$branch' is protected"
        return 0; } ;;
  esac

  git add -A 2>/dev/null
  if git diff --cached --quiet 2>/dev/null; then
    return 0  # nothing to commit
  fi

  local count
  count=$(git diff --cached --name-only | wc -l | tr -d ' ')

  if ! git commit --quiet -m "chore(autosync): wip from clrepo session ($(date -Iminutes))" 2>/dev/null; then
    _autosync_warn "commit failed in $repo_name on $branch"
    _autosync_telegram "$token" "⚠️ autosync FAILED in ${repo_name} on ${branch}: commit error"
    return 0
  fi

  if ! git push --quiet 2>/dev/null; then
    _autosync_warn "push failed in $repo_name on $branch"
    _autosync_telegram "$token" "⚠️ autosync FAILED in ${repo_name} on ${branch}: push rejected"
    return 0
  fi

  _autosync_ok "pushed ${count} file(s) to ${branch} in ${repo_name}"
  _autosync_telegram "$token" "💾 autosync: pushed ${count} change(s) to ${branch} in ${repo_name}"
}

# Script mode: tmux session-closed hook entry point.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  session="${1:-}"
  token="${2:-}"
  [ -z "$session" ] && exit 0
  path_file="$_CLREPO_CACHE/sessions/${session}.path"
  [ -f "$path_file" ] || exit 0
  repo_path=$(<"$path_file")
  rm -f "$path_file"
  _clrepo_autosync "$repo_path" "$token"
fi
