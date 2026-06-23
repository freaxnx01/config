#!/usr/bin/env bash
# setup/00-claude-partials.sh
#
# Ensure the shared Claude Code partials in this repo are cloned at the
# canonical path AND @-included in your user-level CLAUDE.md (~/.claude/CLAUDE.md).
#
# Idempotent: re-running it pulls the latest partials and rewrites the marker
# block in place. Safe to run on every machine.
#
# Usage (existing machine, repo already cloned):
#   ~/repos/github/freaxnx01/public/config/setup/00-claude-partials.sh
#
# Usage (new machine, nothing cloned yet — single-line bootstrap):
#   curl -fsSL https://raw.githubusercontent.com/freaxnx01/config/main/setup/00-claude-partials.sh | bash

set -euo pipefail

REPO_URL="https://github.com/freaxnx01/config.git"
REPO_DIR="$HOME/repos/github/freaxnx01/public/config"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"

# Partials to @-include. Use ~/... so Claude resolves the path on whatever
# machine you're on (WSL2/Linux and Windows both expand ~ to the home dir).
PARTIALS=(
  "~/repos/github/freaxnx01/public/config/claude/task-checklist.md"
  "~/repos/github/freaxnx01/public/config/claude/skill-authoring.md"
  "~/repos/github/freaxnx01/public/config/claude/subagent-driven-default.md"
)

BEGIN="<!-- BEGIN provisioned:claude-partials (managed by setup/00-claude-partials.sh) -->"
END="<!-- END provisioned:claude-partials -->"

# 1) Clone or fast-forward the config repo at the canonical path.
if [ ! -d "$REPO_DIR/.git" ]; then
  echo "→ cloning config repo to $REPO_DIR"
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone "$REPO_URL" "$REPO_DIR"
else
  echo "→ pulling latest at $REPO_DIR"
  git -C "$REPO_DIR" pull --ff-only
fi

# 2) Make sure ~/.claude/CLAUDE.md exists.
mkdir -p "$(dirname "$CLAUDE_MD")"
[ -f "$CLAUDE_MD" ] || : > "$CLAUDE_MD"

# 3) Compose the desired marker block.
block_file="$(mktemp)"
tmp="$(mktemp)"
trap 'rm -f "$block_file" "$tmp"' EXIT
{
  printf '%s\n' "$BEGIN"
  for p in "${PARTIALS[@]}"; do printf '@%s\n' "$p"; done
  printf '%s\n' "$END"
} > "$block_file"

# 4) Normalize the file in a single awk pass:
#    - Strip any existing managed block (lines between BEGIN and END markers).
#    - Strip any free-floating @-include lines that match the partials we manage
#      (migrates legacy un-managed lines into the canonical block).
#    Then append the fresh managed block.
echo "→ normalizing $CLAUDE_MD"
awk -v beg="$BEGIN" -v end="$END" \
    -v partials_list="$(printf '%s\n' "${PARTIALS[@]}")" '
  BEGIN {
    n = split(partials_list, arr, "\n")
    for (i=1; i<=n; i++) if (arr[i] != "") managed["@" arr[i]] = 1
  }
  $0 == beg { skip=1; next }
  $0 == end { skip=0; next }
  skip      { next }
  ($0 in managed) { next }
  { print }
' "$CLAUDE_MD" > "$tmp"

# Trim trailing blank lines so re-runs are byte-idempotent (otherwise each run
# accumulates an extra blank line before the block).
awk 'BEGIN{n=0} {buf[++n]=$0} END{
  while (n>0 && buf[n]=="") n--
  for (i=1; i<=n; i++) print buf[i]
}' "$tmp" > "$tmp.trim" && mv "$tmp.trim" "$tmp"

# Append exactly one separating blank line + the managed block.
[ -s "$tmp" ] && printf '\n' >> "$tmp"
cat "$block_file" >> "$tmp"
mv "$tmp" "$CLAUDE_MD"

echo "✓ done — start a new Claude Code session to pick up the partials"
