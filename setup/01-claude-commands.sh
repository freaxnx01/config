#!/usr/bin/env bash
# setup/01-claude-commands.sh
#
# Install the user-level Claude Code slash commands into ~/.claude/commands/.
#
# As of the 2026-07-21 consolidation, ALL commands live in freaxnx01/agent-workflow.
# This script remains the single bootstrap entry point: it clones that repo if
# absent and calls its link step. config itself ships no commands.
#
# Unlike partials, slash commands cannot be @-included — they must physically
# live in ~/.claude/commands/. Default is symlink (a `git pull` here then updates
# every machine instantly); pass --copy where symlinks are awkward (native Windows).
#
# Idempotent: re-running refreshes the links/copies. Safe to run on every machine.
#
# Usage (existing machine, repo already cloned):
#   ~/repos/github/freaxnx01/public/config/setup/01-claude-commands.sh [--copy]
#
# Usage (new machine, nothing cloned yet — single-line bootstrap):
#   curl -fsSL https://raw.githubusercontent.com/freaxnx01/config/main/setup/01-claude-commands.sh | bash

set -euo pipefail

REPO_URL="https://github.com/freaxnx01/config.git"
REPO_DIR="$HOME/repos/github/freaxnx01/public/config"

mode="link"
sync=1
for arg in "$@"; do
  case "$arg" in
    --copy)    mode="copy" ;;
    --no-sync) sync=0 ;;
  esac
done

# 1) Clone or fast-forward the config repo at the canonical path (unless --no-sync).
if [ "$sync" = 1 ]; then
  if [ ! -d "$REPO_DIR/.git" ]; then
    echo "→ cloning config repo to $REPO_DIR"
    mkdir -p "$(dirname "$REPO_DIR")"
    git clone "$REPO_URL" "$REPO_DIR"
  else
    echo "→ pulling latest at $REPO_DIR"
    git -C "$REPO_DIR" pull --ff-only
  fi
fi

# 2) Install ALL user-level commands from agent-workflow. config no longer ships
#    commands of its own -- the whole surface consolidated there. config stays the
#    single bootstrap orchestrator by cloning it if absent and calling its link step, so the
#    "one curl sets up a machine" promise survives.
AP_REPO_URL="https://github.com/freaxnx01/agent-workflow.git"
AP_REPO_DIR="$HOME/repos/github/freaxnx01/public/agent-workflow"
AP_LINK="$AP_REPO_DIR/setup/link-commands.sh"

if [ "$sync" = 1 ] && [ ! -d "$AP_REPO_DIR/.git" ]; then
  echo "→ cloning agent-workflow repo to $AP_REPO_DIR (for console commands)"
  mkdir -p "$(dirname "$AP_REPO_DIR")"
  git clone "$AP_REPO_URL" "$AP_REPO_DIR"
fi

if [ -f "$AP_LINK" ]; then
  ap_args=()
  [ "$mode" = "copy" ] && ap_args+=(--copy)
  [ "$sync" = 0 ] && ap_args+=(--no-sync)
  echo "→ linking agent-workflow console commands via $AP_LINK"
  bash "$AP_LINK" ${ap_args[@]+"${ap_args[@]}"}
else
  echo "⚠ agent-workflow link step not found at $AP_LINK — console commands (gh:/fj:/routers) NOT installed." >&2
  echo "  Clone https://github.com/freaxnx01/agent-workflow and re-run, or run with sync enabled." >&2
fi

echo "✓ done — type / in any project to see the commands (all from agent-workflow)"
