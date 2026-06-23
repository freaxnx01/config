#!/usr/bin/env bash
# Install the shared slash commands into your user-level Claude Code commands dir.
#
# Default is symlink mode: ~/.claude/commands/<cmd>.md -> this repo, so a
# `git pull` here updates every machine instantly. Pass --copy for a plain copy
# (use on native Windows or anywhere symlinks are awkward).
#
# Usage:
#   ./install.sh            # symlink each command into ~/.claude/commands/
#   ./install.sh --copy     # copy instead of symlink
set -euo pipefail

mode="link"
[[ "${1:-}" == "--copy" ]] && mode="copy"

src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dest_dir="${HOME}/.claude/commands"
mkdir -p "$dest_dir"

for f in "$src_dir"/*.md; do
  name="$(basename "$f")"
  dest="$dest_dir/$name"
  if [[ "$mode" == "copy" ]]; then
    cp -f "$f" "$dest"
    echo "copied  $name"
  else
    ln -sfn "$f" "$dest"
    echo "linked  $name -> $f"
  fi
done

echo "Done. Run /loose-ends or /clear-check in any project."
