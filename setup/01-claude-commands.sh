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
[ "${1:-}" = "--copy" ] && mode="copy"

# 1) Clone or fast-forward the config repo at the canonical path.
if [ ! -d "$REPO_DIR/.git" ]; then
  echo "→ cloning config repo to $REPO_DIR"
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone "$REPO_URL" "$REPO_DIR"
else
  echo "→ pulling latest at $REPO_DIR"
  git -C "$REPO_DIR" pull --ff-only
fi

# 2) Make sure ~/.claude/commands/ exists.
mkdir -p "$DEST_DIR"

# 3) Install each command .md (skip this dir's README).
echo "→ installing commands into $DEST_DIR ($mode)"
for f in "$SRC_DIR"/*.md; do
  name="$(basename "$f")"
  [ "$name" = "README.md" ] && continue
  dest="$DEST_DIR/$name"
  if [ "$mode" = "copy" ]; then
    cp -f "$f" "$dest"
    echo "  copied  $name"
  else
    ln -sfn "$f" "$dest"
    echo "  linked  $name"
  fi
done

echo "✓ done — type / in any project to see the commands (e.g. /loose-ends, /clear-check)"
