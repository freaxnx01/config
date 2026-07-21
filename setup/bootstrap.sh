#!/usr/bin/env bash
# setup/bootstrap.sh — one-shot setup of everything in this repo for a new machine.
#
# Clones (or pulls) the config repo, then runs all setup steps in order:
#   00 partials  → @-imports into ~/.claude/CLAUDE.md
#   01 commands  → slash commands into ~/.claude/commands/  (pass --copy for Windows)
#   02 hooks     → handoff-resume SessionStart(clear) hook + settings.json wiring
#
# Idempotent — safe to re-run to update a machine after a `git pull`.
#
# New machine, nothing cloned yet (single line):
#   curl -fsSL https://raw.githubusercontent.com/freaxnx01/config/main/setup/bootstrap.sh | bash
#
# Windows / no-symlink filesystems:
#   curl -fsSL .../setup/bootstrap.sh | bash -s -- --copy

set -euo pipefail

REPO_URL="https://github.com/freaxnx01/config.git"
REPO_DIR="$HOME/repos/github/freaxnx01/public/config"

if [ ! -d "$REPO_DIR/.git" ]; then
  echo "→ cloning config repo to $REPO_DIR"
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone "$REPO_URL" "$REPO_DIR"
else
  echo "→ pulling latest at $REPO_DIR"
  git -C "$REPO_DIR" pull --ff-only
fi

bash "$REPO_DIR/setup/00-claude-partials.sh"
bash "$REPO_DIR/setup/01-claude-commands.sh" "$@"
bash "$REPO_DIR/setup/02-claude-hooks.sh"
bash "$REPO_DIR/setup/03-claude-skills.sh"

echo
echo "✓ bootstrap complete — start a new Claude Code session, then run /commands and /memory to verify."
