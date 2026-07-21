#!/usr/bin/env bash
# setup/02-claude-hooks.sh
#
# Install the Claude Code hooks into ~/.claude/hooks/ and wire them into
# ~/.claude/settings.json.
#
# As of the 2026-07-21 consolidation the hooks live in freaxnx01/agent-workflow,
# alongside the commands they pair with — `handoff-resume` is the other half of
# /handoff and /pickup, and splitting a command from its hook across repos is
# worse than keeping both in one place. This script remains a bootstrap entry
# point: it clones that repo if absent and calls its own hook link step.
#
# Idempotent: re-running refreshes the scripts and is a no-op on settings.json if
# the hook is already wired. Needs jq (also required by the hook at runtime).
#
# Usage (existing machine, repo already cloned):
#   ~/repos/github/freaxnx01/public/config/setup/02-claude-hooks.sh [--no-sync]
#
# Usage (new machine, nothing cloned yet — single-line bootstrap):
#   curl -fsSL https://raw.githubusercontent.com/freaxnx01/config/main/setup/02-claude-hooks.sh | bash

set -euo pipefail

AP_REPO_URL="https://github.com/freaxnx01/agent-workflow.git"
AP_REPO_DIR="$HOME/repos/github/freaxnx01/public/agent-workflow"
AP_LINK="$AP_REPO_DIR/setup/link-hooks.sh"

sync=1
for arg in "$@"; do
  case "$arg" in
    --no-sync) sync=0 ;;
  esac
done

# Clone agent-workflow if absent, so the "one curl sets up a machine" promise
# survives the hooks living in a separate repo.
if [ "$sync" = 1 ] && [ ! -d "$AP_REPO_DIR/.git" ]; then
  echo "→ cloning agent-workflow repo to $AP_REPO_DIR (for hooks)"
  mkdir -p "$(dirname "$AP_REPO_DIR")"
  git clone "$AP_REPO_URL" "$AP_REPO_DIR"
fi

if [ ! -f "$AP_LINK" ]; then
  echo "⚠ agent-workflow hook link step not found at $AP_LINK — hooks NOT installed." >&2
  echo "  Clone https://github.com/freaxnx01/agent-workflow and re-run, or run with sync enabled." >&2
  exit 1
fi

ap_args=()
[ "$sync" = 0 ] && ap_args+=(--no-sync)

echo "→ installing hooks via $AP_LINK"
bash "$AP_LINK" ${ap_args[@]+"${ap_args[@]}"}
