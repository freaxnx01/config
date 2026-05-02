#!/usr/bin/env bash
# clrepo usage-limit watcher.
#
# Polls each occupied slot's tmux pane every POLL_SEC for the usage-limit
# phrase. On match (and gate-permitting), sends a Telegram page via the
# slot's bot. Self-exits when no slots are occupied for two consecutive
# polls (60s grace).

set -u

CACHE="$HOME/.cache/clrepo"
LOG="$CACHE/watcher.log"
PID_FILE="$CACHE/watcher.pid"
SLOTS_FILE="$CACHE/slots.json"
POLL_SEC=30

# Self-locate clrepo.sh and source it for helpers.
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLREPO_SH="$HOOK_DIR/clrepo.sh"
# shellcheck disable=SC1090
. "$CLREPO_SH" 2>/dev/null || {
  echo "watcher: cannot source $CLREPO_SH" >&2
  exit 1
}

# Usage-limit detection: literal substring match. Initial pattern is the
# common Claude Code wording. Tune as needed; logs all candidate pane snapshots
# until confirmed (see hooks.log / watcher.log for first real fire).
LIMIT_PATTERNS=(
  "Claude usage limit reached"
  "5-hour limit reached"
)

log() { printf '[%s] %s\n' "$(date -Iseconds)" "$*" >>"$LOG" 2>/dev/null; }

# Refuse to start a second instance
if [ -f "$PID_FILE" ]; then
  if kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    log "another watcher (pid $(cat "$PID_FILE")) is already running, exiting"
    exit 0
  fi
fi
echo $$ > "$PID_FILE"
trap 'rm -f "$PID_FILE"; log "watcher exiting"' EXIT

log "watcher starting (pid $$)"

empty_polls=0

while :; do
  # Rotate log if > 1MB
  if [ -f "$LOG" ] && [ "$(stat -c %s "$LOG" 2>/dev/null || echo 0)" -gt 1048576 ]; then
    mv "$LOG" "${LOG}.1" 2>/dev/null
  fi

  # Iterate active slots
  mapfile -t active < <(python3 -c "
import json
try:
    with open('$SLOTS_FILE') as f: d = json.load(f)
    for n, v in (d.get('slots') or {}).items():
        if v and v.get('session'):
            print(f\"{n}\t{v['session']}\")
except Exception:
    pass
" 2>/dev/null)

  if [ "${#active[@]}" -eq 0 ]; then
    empty_polls=$((empty_polls + 1))
    log "no active slots (empty_polls=$empty_polls)"
    [ "$empty_polls" -ge 2 ] && { log "self-exit"; exit 0; }
    sleep "$POLL_SEC"
    continue
  fi
  empty_polls=0

  for entry in "${active[@]}"; do
    slot="${entry%%	*}"
    sess="${entry##*	}"

    # Skip if already paged this session
    [ -f "$CACHE/sessions/${slot}.limit-paged" ] && continue

    # Capture pane (last 2000 lines of scrollback)
    pane=$(tmux capture-pane -p -S -2000 -t "$sess" 2>/dev/null) || continue

    matched=0
    for pat in "${LIMIT_PATTERNS[@]}"; do
      if printf '%s' "$pane" | grep -Fq "$pat"; then
        matched=1
        log "MATCH slot=$slot pattern=$pat"
        break
      fi
    done

    [ "$matched" -eq 1 ] || continue

    # Gate
    if ! _clrepo_should_page "$slot"; then
      log "slot=$slot matched but gate says present, skip"
      touch "$CACHE/sessions/${slot}.limit-paged"  # still mark to dedup if user steps away later
      continue
    fi

    # Build snippet via the same logic as notify.sh (inline since we can't easily import it)
    snippet=$(printf '%s' "$pane" | sed 's/\x1b\[[0-9;]*[mGKH]//g' | grep -v '^[[:space:]]*$' | tail -12 | tr -d '\r')
    snippet="${snippet:0:500}"
    repo=$(python3 -c "
import json
try:
    with open('$SLOTS_FILE') as f: d = json.load(f)
    v = (d.get('slots') or {}).get('$slot') or {}
    print(v.get('repo') or '?')
except Exception:
    print('?')
" 2>/dev/null)
    wt=$(python3 -c "
import json
try:
    with open('$SLOTS_FILE') as f: d = json.load(f)
    v = (d.get('slots') or {}).get('$slot') or {}
    print(v.get('worktree') or '')
except Exception:
    pass
" 2>/dev/null)
    bracket="s${slot}/${repo}"
    [ -n "$wt" ] && bracket="$bracket worktree:$wt"

    body="🛑 Usage limit reached [${bracket}]"
    [ -n "$snippet" ] && body="${body}

Last:
> ${snippet//$'\n'/$'\n'> }"

    _clrepo_telegram_page "$slot" "$body"
    touch "$CACHE/sessions/${slot}.limit-paged"
    log "sent limit page slot=$slot"
  done

  sleep "$POLL_SEC"
done
