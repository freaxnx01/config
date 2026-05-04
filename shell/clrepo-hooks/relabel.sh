#!/usr/bin/env bash
# SessionStart hook (matcher: "clear") — emit additionalContext asking
# Claude to restore the session display label after /clear wipes it.
#
# Args: $1 = slot number (passed by the install command in settings.json)
# Stdin: Claude Code hook payload (consumed but not used).
#
# Label source:
#   - $CLAUDE_CONFIG_DIR/clrepo-label (written by clrepo at launch for
#     slots 1..N; user-managed for slot 0 admin sessions).
# Falls back to silent no-op if the file is missing.

set -u

SLOT="${1:-}"
CACHE="${CLREPO_CACHE:-$HOME/.cache/clrepo}"
LOG="$CACHE/hooks.log"

log() { printf '[%s] relabel(s%s): %s\n' "$(date -Iseconds)" "$SLOT" "$*" >>"$LOG" 2>/dev/null; }

# Drain stdin so the launcher doesn't block on SIGPIPE.
cat >/dev/null 2>&1

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude-s${SLOT}}"
LABEL_FILE="$CFG/clrepo-label"
[ -f "$LABEL_FILE" ] || { log "no label file at $LABEL_FILE"; exit 0; }

LABEL=$(tr -d '\n' < "$LABEL_FILE")
[ -z "$LABEL" ] && { log "label file empty"; exit 0; }

# Hook output schema: a JSON object whose hookSpecificOutput.additionalContext
# is appended to Claude's context for the next turn. Phrase as a direct
# user-style instruction to maximise the chance that Claude actually
# invokes `/rename`.
python3 -c "
import json, sys
label = sys.argv[1]
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'SessionStart',
        'additionalContext': (
            f'/clear was just invoked, which wipes the Claude Code session '
            f'display label. Please restore it now by running this slash '
            f'command exactly: /rename {label}'
        )
    }
}))
" "$LABEL"

log "emitted relabel hint for label='$LABEL'"
exit 0
