#!/usr/bin/env bash
# setup/02-claude-hooks.sh
#
# Install the handoff-resume SessionStart(clear) hook: copy the script to
# ~/.claude/hooks/ AND wire it into ~/.claude/settings.json (matcher "clear").
#
# Idempotent: re-running refreshes the script and is a no-op on settings.json if
# the hook is already wired. settings.json is backed up before any edit, and left
# untouched if it isn't valid JSON. Needs jq (also required by the hook at runtime).
#
# Usage (existing machine, repo already cloned):
#   ~/repos/github/freaxnx01/public/config/setup/02-claude-hooks.sh
#
# Usage (new machine, nothing cloned yet — single-line bootstrap):
#   curl -fsSL https://raw.githubusercontent.com/freaxnx01/config/main/setup/02-claude-hooks.sh | bash

set -euo pipefail

REPO_URL="https://github.com/freaxnx01/config.git"
REPO_DIR="$HOME/repos/github/freaxnx01/public/config"
SRC="$REPO_DIR/claude/hooks/handoff-resume.sh"
HOOK_DIR="$HOME/.claude/hooks"
DEST="$HOOK_DIR/handoff-resume.sh"
SETTINGS="$HOME/.claude/settings.json"
CMD='$HOME/.claude/hooks/handoff-resume.sh'

# 1) Clone or fast-forward the config repo at the canonical path.
if [ ! -d "$REPO_DIR/.git" ]; then
  echo "→ cloning config repo to $REPO_DIR"
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone "$REPO_URL" "$REPO_DIR"
else
  echo "→ pulling latest at $REPO_DIR"
  git -C "$REPO_DIR" pull --ff-only
fi

# 2) Install the hook script.
mkdir -p "$HOOK_DIR"
cp -f "$SRC" "$DEST"
chmod +x "$DEST"
echo "→ installed hook script to $DEST"

# 3) Wire it into settings.json (or print the snippet if jq is unavailable).
snippet='   { "matcher": "clear", "hooks": [ { "type": "command", "command": "'"$CMD"'" } ] }'
if ! command -v jq >/dev/null 2>&1; then
  echo "⚠ jq not found — add this to $SETTINGS under hooks.SessionStart, then install jq:"
  echo "$snippet"
  exit 0
fi

[ -f "$SETTINGS" ] || { mkdir -p "$(dirname "$SETTINGS")"; echo '{}' > "$SETTINGS"; }
if ! jq -e . "$SETTINGS" >/dev/null 2>&1; then
  echo "⚠ $SETTINGS is not valid JSON — leaving it untouched. Add manually:"
  echo "$snippet"
  exit 1
fi

# Match by script basename, not exact string, so an existing entry written with an
# absolute path (or different $HOME spelling) still counts as present — avoids a
# near-duplicate that would inject the resume context twice.
present='([ (.hooks.SessionStart // [])[] | select(.matcher? == "clear") | .hooks[]? | .command? | select(. != null) | select(test("handoff-resume\\.sh")) ] | length) > 0'
if jq -e "$present" "$SETTINGS" >/dev/null 2>&1; then
  echo "✓ settings.json already wires the hook — nothing to do"
  exit 0
fi

cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
tmp="$(mktemp)"
jq --arg c "$CMD" '
  .hooks = (.hooks // {})
  | .hooks.SessionStart = (.hooks.SessionStart // [])
  | (.hooks.SessionStart | map(.matcher? == "clear") | index(true)) as $i
  | if $i == null
    then .hooks.SessionStart += [{matcher:"clear", hooks:[{type:"command", command:$c}]}]
    else .hooks.SessionStart[$i].hooks = ((.hooks.SessionStart[$i].hooks // []) + [{type:"command", command:$c}])
    end
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
echo "✓ wired hook into $SETTINGS (backup saved alongside it)"
