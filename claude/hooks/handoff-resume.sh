#!/usr/bin/env bash
# SessionStart(clear) hook — pairs with the /handoff and /pickup commands.
#
# When you /clear, this checks the cleared project for .claude/handoff.md and, if
# present, injects it as additionalContext so the resume prompt is already loaded
# (you just type /pickup or "go" — no clipboard paste needed).
#
# Wire it up in ~/.claude/settings.json under hooks.SessionStart with
# matcher "clear":
#   { "type": "command", "command": "$HOME/.claude/hooks/handoff-resume.sh" }
#
# A command/skill CANNOT run /clear or auto-send a prompt itself — that's why this
# is a passive context injection, not an auto-trigger.
set -euo pipefail

input="$(cat)"
dir="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -z "$dir" ] && dir="${CLAUDE_PROJECT_DIR:-$PWD}"
f="$dir/.claude/handoff.md"
[ -f "$f" ] || exit 0

jq -n --rawfile c "$f" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: ("Resume context from a prior /handoff. Read the referenced spec/plan in .claude/handoff.md and continue, subagent-driven:\n\n" + $c)
  }
}'
