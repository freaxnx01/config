#!/usr/bin/env bash
# UserPromptSubmit hook for clrepo presence-aware Telegram pages.
#
# Removes the per-slot idle marker so a debounced page that hasn't
# fired yet is silently cancelled.
#
# Args: $1 = slot number (passed via the hook command in settings.json)
# Stdin: Claude Code hook payload (JSON) — not consumed; drained.

set -u

SLOT="${1:-}"
CACHE="$HOME/.cache/clrepo"
LOG="$CACHE/hooks.log"

# Drain stdin so Claude Code doesn't see a SIGPIPE
cat >/dev/null 2>&1 || true

[ -z "$SLOT" ] && {
  printf '[%s] clear-idle: missing slot arg\n' "$(date -Iseconds)" >>"$LOG" 2>/dev/null
  exit 0
}

rm -f "$CACHE/sessions/${SLOT}.idle-since" 2>/dev/null

# Rotate log if > 1MB
if [ -f "$LOG" ] && [ "$(stat -c %s "$LOG" 2>/dev/null || echo 0)" -gt 1048576 ]; then
  mv "$LOG" "${LOG}.1" 2>/dev/null
fi

exit 0
