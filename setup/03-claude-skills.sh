#!/usr/bin/env bash
# setup/03-claude-skills.sh
#
# Install the user-level Claude Code agent skills into ~/.claude/skills/.
#
# As of the 2026-07-21 consolidation the skills live in freaxnx01/agent-workflow,
# alongside the commands they pair with — `processing-test-feedback` is the other
# half of /process-feedback, and splitting a command from the skill it delegates
# to across repos is worse than keeping both in one place. This script remains a
# bootstrap entry point: it clones that repo if absent and calls its own skill
# link step.
#
# Distinct from the plugin skills in freaxnx01/agent-skills, which install through
# /plugin into the plugin cache and are not touched here.
#
# Idempotent: re-running refreshes the installed copies.
#
# Usage (existing machine, repo already cloned):
#   ~/repos/github/freaxnx01/public/config/setup/03-claude-skills.sh [--no-sync]
#
# Usage (new machine, nothing cloned yet — single-line bootstrap):
#   curl -fsSL https://raw.githubusercontent.com/freaxnx01/config/main/setup/03-claude-skills.sh | bash

set -euo pipefail

AP_REPO_URL="https://github.com/freaxnx01/agent-workflow.git"
AP_REPO_DIR="$HOME/repos/github/freaxnx01/public/agent-workflow"
AP_LINK="$AP_REPO_DIR/setup/link-skills.sh"

sync=1
for arg in "$@"; do
  case "$arg" in
    --no-sync) sync=0 ;;
  esac
done

# Clone agent-workflow if absent, so the "one curl sets up a machine" promise
# survives the skills living in a separate repo.
if [ "$sync" = 1 ] && [ ! -d "$AP_REPO_DIR/.git" ]; then
  echo "→ cloning agent-workflow repo to $AP_REPO_DIR (for skills)"
  mkdir -p "$(dirname "$AP_REPO_DIR")"
  git clone "$AP_REPO_URL" "$AP_REPO_DIR"
fi

if [ ! -f "$AP_LINK" ]; then
  echo "⚠ agent-workflow skill link step not found at $AP_LINK — skills NOT installed." >&2
  echo "  Clone https://github.com/freaxnx01/agent-workflow and re-run, or run with sync enabled." >&2
  exit 1
fi

ap_args=()
[ "$sync" = 0 ] && ap_args+=(--no-sync)

echo "→ installing skills via $AP_LINK"
bash "$AP_LINK" ${ap_args[@]+"${ap_args[@]}"}
