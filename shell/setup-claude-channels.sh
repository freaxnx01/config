#!/usr/bin/env bash
# setup-claude-channels.sh — interactive setup for clrepo Telegram channels.
#
# Writes ~/.cache/clrepo/owner.json (Telegram user_id) and
# ~/.cache/clrepo/slot-tokens.json (per-slot Passbolt resource IDs).
# Idempotent: re-run anytime to add slots, rotate tokens, or change owner.
#
# slots.json is NOT touched here — clrepo self-inits it on first use.

set -eu

CACHE="${CLREPO_CACHE:-$HOME/.cache/clrepo}"
OWNER="$CACHE/owner.json"
TOKENS="$CACHE/slot-tokens.json"
MAX="${CLREPO_MAX_SLOTS:-6}"

mkdir -p "$CACHE"

command -v passbolt >/dev/null 2>&1 || { echo "ERR: passbolt CLI not on PATH" >&2; exit 1; }
command -v python3  >/dev/null 2>&1 || { echo "ERR: python3 not on PATH" >&2; exit 1; }

prompt_default() {
  local prompt="$1" default="${2:-}" ans
  if [ -n "$default" ]; then
    read -r -p "$prompt [$default]: " ans
    printf '%s' "${ans:-$default}"
  else
    read -r -p "$prompt: " ans
    printf '%s' "$ans"
  fi
}

validate_passbolt() {
  passbolt get resource --id "$1" 2>/dev/null \
    | awk -F': ' '/^Password:/ {found=1} END{exit !found}'
}

json_read() {
  python3 -c '
import json, sys, os
f = sys.argv[1]
print(json.dumps(json.load(open(f))) if os.path.exists(f) else "{}")
' "$1"
}

json_get() {
  python3 -c '
import json, sys
print(json.load(sys.stdin).get(sys.argv[1], ""))
' "$1"
}

json_set() {
  python3 -c '
import json, sys
d = json.load(sys.stdin)
d[sys.argv[1]] = sys.argv[2]
print(json.dumps(d))
' "$1" "$2"
}

write_atomic() {
  local f="$1"
  python3 -c '
import json, sys
json.dump(json.load(sys.stdin), open(sys.argv[1] + ".tmp", "w"), indent=2, sort_keys=True)
' "$f"
  mv "$f.tmp" "$f"
}

echo "clrepo: setup-claude-channels.sh"
echo "  cache: $CACHE"
echo "  slots: 1..$MAX"
echo

# --- 1. Telegram owner ---
owner_json=$(json_read "$OWNER")
cur_owner=$(printf '%s' "$owner_json" | json_get telegram_user_id)
echo "Telegram owner — your numeric Telegram user_id (find via @userinfobot)."
new_owner=$(prompt_default "  user_id" "$cur_owner")
if [ -z "$new_owner" ]; then
  echo "  (skipped — no owner configured)"
else
  printf '%s' "$owner_json" | json_set telegram_user_id "$new_owner" | write_atomic "$OWNER"
  echo "  ✓ owner.json: $new_owner"
fi
echo

# --- 2. Per-slot bot tokens (Passbolt resource IDs) ---
echo "Per-slot bot tokens — paste the Passbolt resource ID for each bot."
echo "  Slot 0 = admin bot (BotFather-named). Empty = skip; existing values shown as default."
tokens_json=$(json_read "$TOKENS")
result_json="$tokens_json"

for n in $(seq 0 "$MAX"); do
  cur=$(printf '%s' "$tokens_json" | json_get "$n")
  if [ "$n" = 0 ]; then
    echo "  slot 0 (admin bot — empty disables admin-bot title management)"
  else
    echo "  slot $n (@claude_freax_s${n}_bot)"
  fi
  pb_id=$(prompt_default "    Passbolt id" "$cur")
  if [ -z "$pb_id" ]; then
    echo "    (skipped)"
    continue
  fi
  if [ "$pb_id" = "$cur" ]; then
    echo "    (kept existing)"
    continue
  fi
  if validate_passbolt "$pb_id"; then
    result_json=$(printf '%s' "$result_json" | json_set "$n" "$pb_id")
    echo "    ✓ token resolved"
  else
    echo "    ✗ Passbolt id did not resolve to a token — keeping previous (if any)" >&2
  fi
done

printf '%s' "$result_json" | write_atomic "$TOKENS"

slot_list=$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
print(" ".join(sorted(d, key=lambda x: int(x) if x.isdigit() else 10**9)))
' "$TOKENS")

echo
echo "✓ slot-tokens.json: ${slot_list:-(empty)}"
echo "Done. Run 'clrepo --status' to confirm."
