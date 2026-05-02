#!/usr/bin/env bash
# Notification hook for clrepo presence-aware Telegram pages.
#
# Acts only on idle_prompt (debounced 120s) and elicitation_dialog (immediate).
# All other notification types are ignored.
#
# Args: $1 = slot number (passed via the hook command in settings.json)
# Stdin: Claude Code hook payload (JSON) with at least .notification_type or .type.

set -u

SLOT="${1:-}"
CACHE="$HOME/.cache/clrepo"
LOG="$CACHE/hooks.log"
DEBOUNCE_SEC=120

# Source clrepo for _clrepo_should_page, _clrepo_telegram_page, etc.
# Self-locating: hook lives at $_CLREPO_DIR/clrepo-hooks/notify.sh
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLREPO_SH="$(dirname "$HOOK_DIR")/clrepo.sh"
# shellcheck disable=SC1090
. "$CLREPO_SH" 2>/dev/null || {
  printf '[%s] notify: failed to source %s\n' "$(date -Iseconds)" "$CLREPO_SH" >>"$LOG"
  exit 0
}

mkdir -p "$CACHE/sessions"

log() { printf '[%s] notify(s%s): %s\n' "$(date -Iseconds)" "$SLOT" "$*" >>"$LOG" 2>/dev/null; }

[ -z "$SLOT" ] && { log "missing slot arg"; exit 0; }

# Read full payload
PAYLOAD=$(cat 2>/dev/null || true)
log "payload: $PAYLOAD"

# Extract notification_type (or type, depending on schema). Try both.
NTYPE=$(echo "$PAYLOAD" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('notification_type') or d.get('type') or '')
except Exception:
    pass
" 2>/dev/null)

log "notification_type=$NTYPE"

# Build the page text from slot metadata + tmux pane snippet
build_page_text() {
  local slot="$1" header="$2"
  python3 -c "
import json, subprocess, re, sys
slot = '$slot'
header = '''$header'''
try:
    with open('$_CLREPO_SLOTS_FILE') as f: d = json.load(f)
    v = d.get('slots', {}).get(slot) or {}
except Exception:
    v = {}

repo  = v.get('repo')   or '?'
wt    = v.get('worktree') or ''
sess  = v.get('session') or ''

snippet = ''
if sess:
    try:
        out = subprocess.run(['tmux','capture-pane','-p','-t',sess],
                             stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                             timeout=2).stdout.decode('utf-8','replace')
        out = re.sub(r'\x1b\[[0-9;]*[mGKH]', '', out)
        lines = [l.rstrip() for l in out.splitlines() if l.strip()]
        snippet = '\n'.join(lines[-12:])[-500:]
    except Exception:
        pass

bracket = f's{slot}/{repo}'
if wt: bracket += f' worktree:{wt}'
text = f'{header} [{bracket}]'
if snippet:
    text += '\n\nLast:\n> ' + snippet.replace('\n', '\n> ')
print(text)
" 2>/dev/null
}

case "$NTYPE" in
  idle_prompt)
    # Touch marker, schedule delayed check
    touch "$CACHE/sessions/${SLOT}.idle-since"
    log "scheduled debounce check in ${DEBOUNCE_SEC}s"
    (
      sleep "$DEBOUNCE_SEC"
      # Marker still present? user hasn't replied since
      [ -f "$CACHE/sessions/${SLOT}.idle-since" ] || exit 0
      # Re-check the gate — user might have attached during the wait
      _clrepo_should_page "$SLOT" || { log "gate says present at delayed check, skip"; exit 0; }
      TEXT=$(build_page_text "$SLOT" "🤔 Claude is waiting for input")
      _clrepo_telegram_page "$SLOT" "$TEXT"
      log "sent idle_prompt page"
    ) &disown
    ;;
  elicitation_dialog)
    # Immediate, gated
    if _clrepo_should_page "$SLOT"; then
      TEXT=$(build_page_text "$SLOT" "🤔 Claude needs input (elicitation)")
      _clrepo_telegram_page "$SLOT" "$TEXT"
      log "sent elicitation_dialog page"
    else
      log "gate says present, skip elicitation_dialog"
    fi
    ;;
  *)
    log "ignoring type=$NTYPE"
    ;;
esac

# Rotate log if > 1MB
if [ -f "$LOG" ] && [ "$(stat -c %s "$LOG" 2>/dev/null || echo 0)" -gt 1048576 ]; then
  mv "$LOG" "${LOG}.1" 2>/dev/null
fi

exit 0
