#!/usr/bin/env bash
# setup/01-claude-commands.sh
#
# Ensure the shared Claude Code slash commands in this repo are cloned at the
# canonical path AND installed into your user-level commands dir (~/.claude/commands/).
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
SRC_DIR="$REPO_DIR/claude/commands"
DEST_DIR="$HOME/.claude/commands"

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

# 2) Make sure ~/.claude/commands/ exists.
mkdir -p "$DEST_DIR"

# 3) Install each command .md, preserving subdirs (which become /namespace:cmd).
#    Skip any README.md at the top level or inside namespace dirs.
echo "→ installing commands into $DEST_DIR ($mode)"
while IFS= read -r f; do
  rel="${f#"$SRC_DIR"/}"
  case "$rel" in README.md|*/README.md) continue ;; esac
  dest="$DEST_DIR/$rel"
  mkdir -p "$(dirname "$dest")"
  if [ "$mode" = "copy" ]; then
    rm -f "$dest"        # dest may be a symlink from a prior install → cp would error
    cp -f "$f" "$dest"
    echo "  copied  $rel"
  else
    ln -sfn "$f" "$dest"
    echo "  linked  $rel"
  fi
done < <(find "$SRC_DIR" -type f -name '*.md')

# 4) Install the agent-pipeline operator-console commands (issue-workflow routers
#    + gh:/fj: families). They live in a SEPARATE repo now; config stays the single
#    orchestrator by cloning it if absent and calling its own link step, so the
#    "one curl sets up a machine" promise survives.
AP_REPO_URL="https://github.com/freaxnx01/agent-pipeline.git"
AP_REPO_DIR="$HOME/repos/github/freaxnx01/public/agent-pipeline"
AP_LINK="$AP_REPO_DIR/setup/link-commands.sh"

if [ "$sync" = 1 ] && [ ! -d "$AP_REPO_DIR/.git" ]; then
  echo "→ cloning agent-pipeline repo to $AP_REPO_DIR (for console commands)"
  mkdir -p "$(dirname "$AP_REPO_DIR")"
  git clone "$AP_REPO_URL" "$AP_REPO_DIR"
fi

if [ -f "$AP_LINK" ]; then
  ap_args=()
  [ "$mode" = "copy" ] && ap_args+=(--copy)
  [ "$sync" = 0 ] && ap_args+=(--no-sync)
  echo "→ linking agent-pipeline console commands via $AP_LINK"
  bash "$AP_LINK" ${ap_args[@]+"${ap_args[@]}"}
else
  echo "⚠ agent-pipeline link step not found at $AP_LINK — console commands (gh:/fj:/routers) NOT installed." >&2
  echo "  Clone https://github.com/freaxnx01/agent-pipeline and re-run, or run with sync enabled." >&2
fi

echo "✓ done — type / in any project to see the commands (generic from config, console from agent-pipeline)"
