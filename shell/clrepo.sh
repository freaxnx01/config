# clrepo — jump into a repo under ~/projects/repos and launch Claude Code.
#
# Layout: $_CLREPO_BASE/{github/<owner>/(public|private),gitlab/<owner>,git-forgejo}
#
# Discovery: every .envrc under $_CLREPO_BASE whose path matches the layout
# is a "forge target" (credential source + clone destination). Target
# metadata is inferred from the path; no sidecar config.
#
# Surface:
#   - local picker (fast, offline, MRU on top)
#   - -r adds uncloned remote repos (streamed per forge)
#   - Ctrl-N in picker creates a new remote repo (fzf query = seed name)
#   - Ctrl-D in picker deletes a repo (local and/or remote)
#   - --delete / -D is the non-interactive delete shortcut
#   - -w/--worktree NAME passes through to `claude --worktree NAME`
#
# SSH persistence: when $SSH_CONNECTION is set (i.e. you're reaching claude-dev
# from a remote client), the final launch is wrapped in `tmux new-session -A`
# so disconnecting the client leaves the Claude session alive on the host.
# Reconnect and re-run `clrepo <repo>` (or `clrepo <repo> -w <wt>`) to reattach.
#
# The slot/telegram wrapper (see external spec) can replace _clrepo_launch
# wholesale without touching the rest of this file.

_CLREPO_BASE="/home/freax/projects/repos"
_CLREPO_CACHE="$HOME/.cache/clrepo"
_CLREPO_REMOTE_TTL=600  # seconds

# --- Slot / Telegram channel config ---
_CLREPO_MAX_SLOTS="${CLREPO_MAX_SLOTS:-6}"
_CLREPO_SLOTS_FILE="$_CLREPO_CACHE/slots.json"
_CLREPO_SLOTS_LOCK="$_CLREPO_CACHE/slots.lock"
_CLREPO_SLOT_TOKENS="$_CLREPO_CACHE/slot-tokens.json"
_CLREPO_OWNER="$_CLREPO_CACHE/owner.json"

# Emit forge targets: TSV of rel_dir\tforge\towner\tvisibility
_clrepo_targets() {
  find "$_CLREPO_BASE" -type f -name .envrc -printf '%h\n' 2>/dev/null \
    | sed "s|^$_CLREPO_BASE/||" \
    | while IFS= read -r rel; do
        case "$rel" in
          github/*/public)
            local o="${rel#github/}"; o="${o%/public}"
            printf '%s\tgithub\t%s\tpublic\n' "$rel" "$o" ;;
          github/*/private)
            local o="${rel#github/}"; o="${o%/private}"
            printf '%s\tgithub\t%s\tprivate\n' "$rel" "$o" ;;
          gitlab/*)
            printf '%s\tgitlab\t%s\t-\n' "$rel" "${rel#gitlab/}" ;;
          git-forgejo)
            printf '%s\tforgejo\tfreax\t-\n' "$rel" ;;
        esac
      done
}

# Fetch remote repo names for one target (loaded via direnv in a subshell).
# Emits: <rel_target>/<repo_name> per line.
_clrepo_fetch_target() {
  local rel="$1" forge="$2" owner="$3" vis="$4"
  (
    cd "$_CLREPO_BASE/$rel" 2>/dev/null || exit
    command -v direnv >/dev/null && eval "$(direnv export bash 2>/dev/null)"
    case "$forge" in
      github)
        local tok="${GH_TOKEN:-$GITHUB_TOKEN}"
        [ -z "$tok" ] && exit
        curl -sf -H "Authorization: token $tok" \
          -H "Accept: application/vnd.github+json" \
          "https://api.github.com/user/repos?affiliation=owner&visibility=$vis&per_page=100" \
          | jq -r --arg rel "$rel" --arg o "$owner" \
              '.[] | select(.owner.login == $o) | "\($rel)/\(.name)"' 2>/dev/null
        ;;
      gitlab)
        [ -z "$GITLAB_TOKEN" ] && exit
        curl -sf -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
          "https://gitlab.freaxnx01.ch/api/v4/projects?owned=true&per_page=100" \
          | jq -r --arg rel "$rel" '.[] | "\($rel)/\(.path)"' 2>/dev/null
        ;;
      forgejo)
        [ -z "$FORGEJO_TOKEN" ] && exit
        curl -sf -H "Authorization: token $FORGEJO_TOKEN" \
          "https://git.home.freaxnx01.ch/api/v1/user/repos?limit=50" \
          | jq -r --arg rel "$rel" '.[] | "\($rel)/\(.name)"' 2>/dev/null
        ;;
    esac
  )
}

# Union of remote listings across all targets, cached with TTL.
# Streams per-forge output to stdout (for live fzf) while also writing
# to a tmp file that becomes the cache on completion.
_clrepo_remote_list() {
  local force="$1"
  local cache="$_CLREPO_CACHE/remote.list"
  local now age
  now=$(date +%s)
  if [ "$force" != 1 ] && [ -f "$cache" ]; then
    age=$(( now - $(stat -c %Y "$cache" 2>/dev/null || echo 0) ))
    if [ "$age" -lt "$_CLREPO_REMOTE_TTL" ]; then
      cat "$cache"; return
    fi
  fi
  echo "clrepo: fetching remote repo listings..." >&2
  local tmp
  tmp=$(mktemp)
  _clrepo_targets | while IFS=$'\t' read -r rel forge owner vis; do
    _clrepo_fetch_target "$rel" "$forge" "$owner" "$vis" | tee -a "$tmp"
  done
  mv "$tmp" "$cache"
}

# Clone-URL for an (existing) remote repo at rel path, inferred from layout.
# GitHub → HTTPS (auth via GH_TOKEN + inline credential helper; no SSH key needed).
# GitLab → HTTPS (auth via GitLab .envrc GIT_CONFIG_* credential helper).
# Forgejo → SSH on port 222 (uses ~/.ssh/id_ed25519_forgejo).
_clrepo_clone_url() {
  local rel="$1"
  local name parent
  name=$(basename "$rel")
  parent=$(dirname "$rel")
  case "$parent" in
    github/*/public|github/*/private)
      local o="${parent#github/}"; o="${o%/public}"; o="${o%/private}"
      printf 'https://github.com/%s/%s.git\n' "$o" "$name" ;;
    gitlab/*)
      printf 'https://gitlab.freaxnx01.ch/%s/%s.git\n' "${parent#gitlab/}" "$name" ;;
    git-forgejo)
      printf 'ssh://git@git.home.freaxnx01.ch:222/freax/%s.git\n' "$name" ;;
    *) return 1 ;;
  esac
}

# Run `git clone` inside a target dir with direnv loaded, injecting a
# GitHub HTTPS credential helper inline when cloning a github/* target.
_clrepo_git_clone_in() {
  local target="$1" url="$2" name="$3"
  (
    cd "$_CLREPO_BASE/$target" || exit 1
    command -v direnv >/dev/null && eval "$(direnv export bash 2>/dev/null)"
    case "$target" in
      github/*)
        [ -z "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ] && { echo "clrepo: no GH_TOKEN under $target" >&2; exit 1; }
        local tok="${GH_TOKEN:-$GITHUB_TOKEN}"
        GH_TOKEN="$tok" git \
          -c "credential.https://github.com.helper=!f() { echo username=x-access-token; echo \"password=\$GH_TOKEN\"; }; f" \
          clone "$url" "$name"
        ;;
      *)
        git clone "$url" "$name"
        ;;
    esac
  )
}

# Clone a known-remote rel into its destination.
_clrepo_clone_remote() {
  local rel="$1"
  local url parent name
  url=$(_clrepo_clone_url "$rel") || { echo "clrepo: unknown forge for $rel"; return 1; }
  parent=$(dirname "$rel")
  name=$(basename "$rel")
  echo "clrepo: cloning $url" >&2
  _clrepo_git_clone_in "$parent" "$url" "$name" || return 1
  rm -f "$_CLREPO_CACHE/remote.list"
}

# Create a new remote repo on a chosen forge target, then clone + launch.
_clrepo_create_new() {
  local seed="$1"
  local targets target
  targets=$(_clrepo_targets | cut -f1)
  [ -z "$targets" ] && { echo "clrepo: no forge targets discovered"; return 1; }
  target=$(printf '%s\n' "$targets" | fzf --height=40% --reverse --prompt='forge target> ') || return
  local name
  read -r -e -i "$seed" -p "repo name: " name
  [ -z "$name" ] && { echo "aborted"; return 1; }

  local line forge vis
  line=$(_clrepo_targets | awk -F'\t' -v t="$target" '$1==t {print; exit}')
  forge=$(printf '%s' "$line" | cut -f2)
  vis=$(printf '%s' "$line" | cut -f4)

  echo "clrepo: creating $name on $target..." >&2
  local url
  url=$(
    cd "$_CLREPO_BASE/$target" || exit
    command -v direnv >/dev/null && eval "$(direnv export bash 2>/dev/null)"
    case "$forge" in
      github)
        local tok="${GH_TOKEN:-$GITHUB_TOKEN}"
        [ -z "$tok" ] && { echo "ERR: no GH_TOKEN under $target" >&2; exit 1; }
        local priv=false; [ "$vis" = "private" ] && priv=true
        curl -sf -X POST \
          -H "Authorization: token $tok" \
          -H "Accept: application/vnd.github+json" \
          -d "$(jq -cn --arg n "$name" --argjson p "$priv" '{name:$n,private:$p,auto_init:false}')" \
          "https://api.github.com/user/repos" \
          | jq -r '.clone_url // empty' ;;
      gitlab)
        [ -z "$GITLAB_TOKEN" ] && { echo "ERR: no GITLAB_TOKEN under $target" >&2; exit 1; }
        curl -sf -X POST \
          -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
          -H "Content-Type: application/json" \
          -d "$(jq -cn --arg n "$name" '{name:$n,path:$n,visibility:"private",initialize_with_readme:false}')" \
          "https://gitlab.freaxnx01.ch/api/v4/projects" \
          | jq -r '.http_url_to_repo // empty' ;;
      forgejo)
        [ -z "$FORGEJO_TOKEN" ] && { echo "ERR: no FORGEJO_TOKEN under $target" >&2; exit 1; }
        curl -sf -X POST \
          -H "Authorization: token $FORGEJO_TOKEN" \
          -H "Content-Type: application/json" \
          -d "$(jq -cn --arg n "$name" '{name:$n,private:true,auto_init:false}')" \
          "https://git.home.freaxnx01.ch/api/v1/user/repos" \
          | jq -r '.ssh_url // empty' ;;
    esac
  )
  [ -z "$url" ] && { echo "clrepo: remote creation failed"; return 1; }
  echo "clrepo: cloning $url" >&2
  _clrepo_git_clone_in "$target" "$url" "$name" || return 1
  rm -f "$_CLREPO_CACHE/remote.list"
  _clrepo_launch "$target/$name"
}

# Delete a repo (local clone and/or remote). `raw` may include the ↓ prefix.
# Safety: requires typing the repo name to confirm remote deletion.
# Refuses local delete if the clone is dirty (uncommitted or unpushed work),
# unless the user types the name a second time to override.
_clrepo_delete() {
  local raw="$1"
  local rel="${raw#↓ }"
  [ -z "$rel" ] && return 1

  local name parent local_path has_local=0 dirty=0
  name=$(basename "$rel")
  parent=$(dirname "$rel")
  local_path="$_CLREPO_BASE/$rel"
  [ -d "$local_path/.git" ] && has_local=1

  # Classify forge + owner from the path.
  local forge owner
  case "$parent" in
    github/*/public|github/*/private)
      forge=github
      owner="${parent#github/}"; owner="${owner%/public}"; owner="${owner%/private}" ;;
    gitlab/*)
      forge=gitlab; owner="${parent#gitlab/}" ;;
    git-forgejo)
      forge=forgejo; owner=freax ;;
    *)
      echo "clrepo: unknown forge for $rel" >&2; return 1 ;;
  esac

  # Dirty check (uncommitted or unpushed).
  if [ "$has_local" = 1 ]; then
    if [ -n "$(git -C "$local_path" status --porcelain 2>/dev/null)" ]; then
      dirty=1
    fi
    local upstream unpushed
    upstream=$(git -C "$local_path" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)
    if [ -n "$upstream" ]; then
      unpushed=$(git -C "$local_path" rev-list --count "$upstream..HEAD" 2>/dev/null)
      [ "${unpushed:-0}" -gt 0 ] && dirty=1
    fi
  fi

  printf 'clrepo: delete target\n' >&2
  printf '  path:   %s\n' "$rel" >&2
  printf '  forge:  %s (%s)\n' "$forge" "$owner" >&2
  printf '  local:  %s%s\n' \
    "$([ "$has_local" = 1 ] && echo yes || echo no)" \
    "$([ "$dirty" = 1 ] && echo ' (DIRTY/unpushed!)' || echo '')" >&2

  local choice
  if [ "$has_local" = 1 ]; then
    read -r -p "Delete [L]ocal / [R]emote / [B]oth / [c]ancel? " choice
  else
    read -r -p "Delete [R]emote / [c]ancel? " choice
    case "$choice" in R|r) ;; *) choice=c ;; esac
  fi

  local del_local=0 del_remote=0
  case "$choice" in
    L|l) del_local=1 ;;
    R|r) del_remote=1 ;;
    B|b) del_local=1; del_remote=1 ;;
    *)   echo "clrepo: cancelled" >&2; return 1 ;;
  esac

  local confirm
  if [ "$del_remote" = 1 ]; then
    read -r -p "Type '$name' to confirm REMOTE delete: " confirm
    [ "$confirm" != "$name" ] && { echo "clrepo: cancelled" >&2; return 1; }
  fi
  if [ "$del_local" = 1 ] && [ "$dirty" = 1 ]; then
    read -r -p "Local is DIRTY. Type '$name' again to override: " confirm
    [ "$confirm" != "$name" ] && { echo "clrepo: cancelled" >&2; return 1; }
  fi

  # Execute remote delete first (if the remote call fails we keep local intact).
  # All three forges use the same direnv-loaded per-dir PAT pattern as clone/create.
  if [ "$del_remote" = 1 ]; then
    echo "clrepo: deleting remote $forge:$owner/$name..." >&2
    (
      local creds_dir
      case "$forge" in
        github)  creds_dir="$_CLREPO_BASE/$parent" ;;
        gitlab)  creds_dir="$_CLREPO_BASE/gitlab/$owner" ;;
        forgejo) creds_dir="$_CLREPO_BASE/git-forgejo" ;;
      esac
      cd "$creds_dir" 2>/dev/null || { echo "ERR: creds dir missing: $creds_dir" >&2; exit 1; }
      command -v direnv >/dev/null && eval "$(direnv export bash 2>/dev/null)"
      case "$forge" in
        github)
          local tok="${GH_TOKEN:-$GITHUB_TOKEN}"
          [ -z "$tok" ] && { echo "ERR: no GH_TOKEN under $parent" >&2; exit 1; }
          local http_code
          http_code=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE \
            -H "Authorization: token $tok" \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/$owner/$name")
          if [ "$http_code" != "204" ]; then
            echo "ERR: GitHub DELETE returned HTTP $http_code" >&2
            if [ "$http_code" = "403" ]; then
              echo "     The PAT under $parent likely lacks 'delete_repo' scope." >&2
              echo "     Fix: https://github.com/settings/tokens → edit the PAT →" >&2
              echo "     tick 'delete_repo' → Update token. Same string, no Passbolt edit." >&2
            fi
            exit 1
          fi
          ;;
        gitlab)
          [ -z "$GITLAB_TOKEN" ] && { echo "ERR: no GITLAB_TOKEN" >&2; exit 1; }
          local enc; enc=$(printf '%s/%s' "$owner" "$name" | jq -sRr '@uri' | tr -d '\n')
          curl -sf -X DELETE \
            -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
            "https://gitlab.freaxnx01.ch/api/v4/projects/$enc" \
            || { echo "ERR: GitLab DELETE failed" >&2; exit 1; }
          ;;
        forgejo)
          [ -z "$FORGEJO_TOKEN" ] && { echo "ERR: no FORGEJO_TOKEN" >&2; exit 1; }
          curl -sf -X DELETE \
            -H "Authorization: token $FORGEJO_TOKEN" \
            "https://git.home.freaxnx01.ch/api/v1/repos/$owner/$name" \
            || { echo "ERR: Forgejo DELETE failed" >&2; exit 1; }
          ;;
      esac
    ) || return 1
    echo "clrepo: remote deleted" >&2
  fi

  if [ "$del_local" = 1 ]; then
    echo "clrepo: removing local $local_path..." >&2
    rm -rf -- "$local_path" || return 1
    if [ -f "$_CLREPO_CACHE/mru" ]; then
      grep -vxF "$rel" "$_CLREPO_CACHE/mru" > "$_CLREPO_CACHE/mru.tmp" 2>/dev/null || : > "$_CLREPO_CACHE/mru.tmp"
      mv "$_CLREPO_CACHE/mru.tmp" "$_CLREPO_CACHE/mru"
    fi
  fi

  rm -f "$_CLREPO_CACHE/remote.list"
  return 0
}

# Final launch step. The slot/telegram wrapper can replace this body later.
#
# Args: $1 = rel repo path (e.g. github/freaxnx01/public/myrepo)
#       $2 = optional worktree name (pass-through to claude --worktree)
#
# When $SSH_CONNECTION is set, wraps the launch in a tmux session named
# after the repo (+worktree), using `new-session -A` so reconnecting and
# re-running the same clrepo command attaches to the live session.
# --- Slot allocation helpers ---

# Read slots.json, reconcile PIDs, return JSON on stdout.
_clrepo_slots_read() {
  local f="$_CLREPO_SLOTS_FILE"
  [ -f "$f" ] || echo '{"slots":{}}' > "$f"
  python3 -c "
import json, os, sys
with open('$f') as fh: d = json.load(fh)
for k, v in d.get('slots', {}).items():
    if v and not _pid_alive(v.get('pid', 0)):
        d['slots'][k] = None
with open('$f', 'w') as fh: json.dump(d, fh, indent=2)
print(json.dumps(d))

def _pid_alive(pid):
    try: os.kill(int(pid), 0); return True
    except: return False
" 2>/dev/null || cat "$f"
}

# Allocate a slot. Sets _SLOT and _SLOT_TOKEN. Optional: $1 = forced slot number.
_clrepo_slot_allocate() {
  local forced="${1:-}"
  local slots_json slot_n now pb_id token

  exec {_lock_fd}>"$_CLREPO_SLOTS_LOCK"
  flock "$_lock_fd"

  # Reconcile dead PIDs
  [ -f "$_CLREPO_SLOTS_FILE" ] || echo '{"slots":{}}' > "$_CLREPO_SLOTS_FILE"
  python3 -c "
import json, os
f = '$_CLREPO_SLOTS_FILE'
with open(f) as fh: d = json.load(fh)
changed = False
for k, v in list(d.get('slots', {}).items()):
    if v:
        try: os.kill(int(v.get('pid', 0)), 0)
        except (ProcessLookupError, ValueError): d['slots'][k] = None; changed = True
        except PermissionError: pass
if changed:
    with open(f, 'w') as fh: json.dump(d, fh, indent=2)
" 2>/dev/null

  slots_json=$(cat "$_CLREPO_SLOTS_FILE")
  now=$(date +%s)

  if [ -n "$forced" ]; then
    # Check if forced slot is free
    local busy
    busy=$(echo "$slots_json" | python3 -c "
import json, sys
d = json.load(sys.stdin)
v = d.get('slots', {}).get('$forced')
if v: print(v.get('repo', '?'))
" 2>/dev/null)
    if [ -n "$busy" ]; then
      echo "clrepo: slot $forced is busy with $busy — use a different slot or clrepo --free $forced" >&2
      flock -u "$_lock_fd"
      return 1
    fi
    _SLOT="$forced"
  else
    # Find lowest free slot
    _SLOT=""
    for n in $(seq 1 "$_CLREPO_MAX_SLOTS"); do
      local val
      val=$(echo "$slots_json" | python3 -c "
import json, sys
d = json.load(sys.stdin)
v = d.get('slots', {}).get('$n')
print('busy' if v else 'free')
" 2>/dev/null)
      if [ "$val" = "free" ] || [ -z "$val" ]; then
        _SLOT="$n"
        break
      fi
    done

    # All busy — displace oldest
    if [ -z "$_SLOT" ]; then
      local oldest_slot oldest_time oldest_repo
      read -r oldest_slot oldest_time oldest_repo < <(echo "$slots_json" | python3 -c "
import json, sys
d = json.load(sys.stdin)
slots = d.get('slots', {})
oldest = min(((k, v) for k, v in slots.items() if v), key=lambda x: x[1].get('started_at', 0))
import time
age = int(time.time()) - oldest[1].get('started_at', 0)
h, m = divmod(age // 60, 60)
print(f\"{oldest[0]} {h}h{m:02d}m {oldest[1].get('repo', '?')}\")
" 2>/dev/null)
      echo "⚠ All $_CLREPO_MAX_SLOTS slots are busy. Displacing slot $oldest_slot ($oldest_repo, running ${oldest_time})." >&2
      echo "  Press Ctrl-C within 5 seconds to abort." >&2
      sleep 5 || { flock -u "$_lock_fd"; return 1; }
      _SLOT="$oldest_slot"
    fi
  fi

  # Load bot token from Passbolt via slot-tokens.json
  _SLOT_TOKEN=""
  if [ -f "$_CLREPO_SLOT_TOKENS" ]; then
    pb_id=$(python3 -c "
import json
with open('$_CLREPO_SLOT_TOKENS') as f: d = json.load(f)
print(d.get('$_SLOT', ''))
" 2>/dev/null)
    if [ -n "$pb_id" ]; then
      _SLOT_TOKEN=$(passbolt get resource --id "$pb_id" 2>/dev/null | awk -F": " '/^Password:/ {print $2}')
    fi
  fi

  flock -u "$_lock_fd"

  if [ -z "$_SLOT_TOKEN" ]; then
    echo "clrepo: WARNING — no bot token for slot $_SLOT. Telegram channel will not work." >&2
    echo "  Run setup-claude-channels.sh or add slot $_SLOT to slot-tokens.json." >&2
  fi
}

# Record slot as busy in slots.json
_clrepo_slot_record() {
  local slot="$1" repo="$2" worktree="${3:-}" pid="$4"
  exec {_lock_fd}>"$_CLREPO_SLOTS_LOCK"
  flock "$_lock_fd"
  python3 -c "
import json, time
f = '$_CLREPO_SLOTS_FILE'
with open(f) as fh: d = json.load(fh)
d.setdefault('slots', {})['$slot'] = {
    'repo': '$repo', 'worktree': '$worktree' or None,
    'pid': $pid, 'started_at': int(time.time())
}
with open(f, 'w') as fh: json.dump(d, fh, indent=2)
" 2>/dev/null
  flock -u "$_lock_fd"
}

# Free a slot in slots.json
_clrepo_slot_free() {
  local slot="$1"
  exec {_lock_fd}>"$_CLREPO_SLOTS_LOCK"
  flock "$_lock_fd"
  python3 -c "
import json
f = '$_CLREPO_SLOTS_FILE'
with open(f) as fh: d = json.load(fh)
d.setdefault('slots', {})['$slot'] = None
with open(f, 'w') as fh: json.dump(d, fh, indent=2)
" 2>/dev/null
  flock -u "$_lock_fd"
}

# Call Telegram API to set bot name and pin a banner message.
_clrepo_telegram_setup() {
  local slot="$1" repo="$2" worktree="${3:-}" token="$4"
  [ -z "$token" ] && return

  local owner_id
  owner_id=$(python3 -c "
import json
with open('$_CLREPO_OWNER') as f: d = json.load(f)
print(d.get('telegram_user_id', ''))
" 2>/dev/null)
  [ -z "$owner_id" ] && return

  local bot_name="Claude · ${repo}"
  [ -n "$worktree" ] && bot_name="Claude · ${repo} [${worktree}]"
  # Truncate to 64 chars (Telegram limit)
  bot_name="${bot_name:0:64}"

  local api="https://api.telegram.org/bot${token}"

  # setMyName (best-effort, rate-limited)
  curl -sf -X POST "$api/setMyName" \
    -H "Content-Type: application/json" \
    -d "$(printf '{"name":"%s"}' "$bot_name")" >/dev/null 2>&1 || true

  # sendMessage + pinChatMessage
  local branch
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "—")
  local msg
  msg=$(printf '📍 Session started\nSlot: s%s\nRepo: %s\nWorktree: %s\nBranch: %s\nPath: %s\nStarted: %s' \
    "$slot" "$repo" "${worktree:-—}" "$branch" "$PWD" "$(date -Iseconds)")

  local send_result msg_id
  send_result=$(curl -sf -X POST "$api/sendMessage" \
    -H "Content-Type: application/json" \
    -d "$(python3 -c "import json; print(json.dumps({'chat_id': '$owner_id', 'text': '''$msg'''}))" 2>/dev/null)" 2>/dev/null) || true

  msg_id=$(echo "$send_result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('result',{}).get('message_id',''))" 2>/dev/null) || true
  if [ -n "$msg_id" ]; then
    curl -sf -X POST "$api/pinChatMessage" \
      -H "Content-Type: application/json" \
      -d "$(printf '{"chat_id":"%s","message_id":%s,"disable_notification":true}' "$owner_id" "$msg_id")" >/dev/null 2>&1 || true
  fi
}

# Best-effort cleanup: reset bot name, send close message.
_clrepo_telegram_cleanup() {
  local slot="$1" token="$2"
  [ -z "$token" ] && return

  local owner_id
  owner_id=$(python3 -c "
import json
with open('$_CLREPO_OWNER') as f: d = json.load(f)
print(d.get('telegram_user_id', ''))
" 2>/dev/null)
  [ -z "$owner_id" ] && return

  local api="https://api.telegram.org/bot${token}"
  curl -sf -X POST "$api/setMyName" \
    -d "$(printf '{"name":"Claude · idle s%s"}' "$slot")" >/dev/null 2>&1 || true
  curl -sf -X POST "$api/sendMessage" \
    -H "Content-Type: application/json" \
    -d "$(printf '{"chat_id":"%s","text":"🛑 Session s%s closed"}' "$owner_id" "$slot")" >/dev/null 2>&1 || true
  curl -sf -X POST "$api/unpinAllChatMessages" \
    -H "Content-Type: application/json" \
    -d "$(printf '{"chat_id":"%s"}' "$owner_id")" >/dev/null 2>&1 || true
}

# Print slot status table.
_clrepo_slot_status() {
  [ -f "$_CLREPO_SLOTS_FILE" ] || { echo "No slots configured. Run setup-claude-channels.sh first." >&2; return 1; }

  # Reconcile PIDs first
  python3 -c "
import json, os
f = '$_CLREPO_SLOTS_FILE'
with open(f) as fh: d = json.load(fh)
for k, v in list(d.get('slots', {}).items()):
    if v:
        try: os.kill(int(v.get('pid', 0)), 0)
        except (ProcessLookupError, ValueError): d['slots'][k] = None
        except PermissionError: pass
with open(f, 'w') as fh: json.dump(d, fh, indent=2)
" 2>/dev/null

  python3 -c "
import json, time
with open('$_CLREPO_SLOTS_FILE') as f: d = json.load(f)
tokens = {}
try:
    with open('$_CLREPO_SLOT_TOKENS') as f: tokens = json.load(f)
except: pass
now = int(time.time())
print(f\"{'SLOT':<5} {'REPO':<30} {'WORKTREE':<15} {'STARTED':<20} {'PID':<8} {'BOT'}\")
print('-' * 95)
for n in sorted(d.get('slots', {}).keys(), key=int):
    v = d['slots'][n]
    pb = tokens.get(n, '')
    bot = f'@claude_freax_s{n}_bot'
    has_token = '✓' if pb else '—'
    if v:
        repo = v.get('repo', '—')
        wt = v.get('worktree') or '—'
        pid = v.get('pid', '—')
        sa = v.get('started_at', 0)
        age = now - sa
        h, m = divmod(age // 60, 60)
        started = f'{h}h{m:02d}m ago' if sa else '—'
        print(f's{n:<4} {repo:<30} {wt:<15} {started:<20} {pid:<8} {bot} {has_token}')
    else:
        print(f's{n:<4} {\"—\":<30} {\"—\":<15} {\"—\":<20} {\"—\":<8} {bot} {has_token}')
" 2>/dev/null
}

_clrepo_launch() {
  local sel="$1"
  local worktree="${2:-}"
  local mru="$_CLREPO_CACHE/mru"
  cd "$_CLREPO_BASE/$sel" || return
  { printf '%s
' "$sel"; grep -vxF "$sel" "$mru" 2>/dev/null; } | head -10 > "$mru.tmp" && mv "$mru.tmp" "$mru"

  local repo
  repo=$(basename "$sel")

  # --- Slot allocation (skip with --no-channel or missing setup) ---
  if [ "${_CLREPO_NO_CHANNEL:-0}" = 1 ] || [ ! -f "$_CLREPO_SLOTS_FILE" ]; then
    # Legacy mode — no slot, no Telegram
    local -a claude_args=(-n "$repo")
    [ -n "$worktree" ] && claude_args+=(--worktree "$worktree")
    if [ -n "${SSH_CONNECTION:-}" ] && command -v tmux >/dev/null; then
      local session="$repo"
      [ -n "$worktree" ] && session="$repo-$worktree"
      session="${session//[^A-Za-z0-9_-]/_}"
      tmux new-session -A -s "$session" claude "${claude_args[@]}"
    else
      claude "${claude_args[@]}"
    fi
    return
  fi

  # Allocate a slot
  _clrepo_slot_allocate "${_CLREPO_FORCED_SLOT:-}" || return

  local -a claude_args=(-n "$repo" --dangerously-skip-permissions --channels plugin:telegram@claude-plugins-official)
  [ -n "$worktree" ] && claude_args+=(--worktree "$worktree")

  export CLAUDE_CONFIG_DIR="$HOME/.claude-s${_SLOT}"
  export TELEGRAM_BOT_TOKEN="$_SLOT_TOKEN"

  echo "clrepo: using slot s${_SLOT} (CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR)" >&2

  if [ -n "${SSH_CONNECTION:-}" ] && command -v tmux >/dev/null; then
    local session="$repo"
    [ -n "$worktree" ] && session="$repo-$worktree"
    session="${session//[^A-Za-z0-9_-]/_}"

    # Reattach if tmux session already exists (no new slot needed)
    if tmux has-session -t "$session" 2>/dev/null; then
      echo "clrepo: reattaching to tmux session '$session' (slot stays as-is)" >&2
      _clrepo_slot_free "$_SLOT"
      tmux attach-session -t "$session"
      return
    fi

    # New tmux session
    _clrepo_telegram_setup "$_SLOT" "$repo" "$worktree" "$_SLOT_TOKEN"
    tmux new-session -d -s "$session"       -e "CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR"       -e "TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN"       claude "${claude_args[@]}"

    local pid
    pid=$(tmux display-message -t "$session" -p '#{pane_pid}' 2>/dev/null || echo 0)
    _clrepo_slot_record "$_SLOT" "$repo" "$worktree" "$pid"
    tmux attach-session -t "$session"
    # On detach: slot stays allocated (claude is still running in tmux).
    # PID reconciliation will free it when claude actually exits.
  else
    # Foreground mode — cleanup on exit
    _clrepo_telegram_setup "$_SLOT" "$repo" "$worktree" "$_SLOT_TOKEN"
    _clrepo_slot_record "$_SLOT" "$repo" "$worktree" "$$"
    claude "${claude_args[@]}"
    _clrepo_slot_free "$_SLOT"
    _clrepo_telegram_cleanup "$_SLOT" "$_SLOT_TOKEN"
  fi
}


clrepo() {
  local with_remote=0 force_refresh=0 mode_delete=0 worktree="" _CLREPO_NO_CHANNEL=0 _CLREPO_FORCED_SLOT=""
  local -a pos=()
  while [ $# -gt 0 ]; do
    case "$1" in
      -r|--remote)    with_remote=1; shift ;;
      --refresh)      with_remote=1; force_refresh=1; shift ;;
      --no-channel)   _CLREPO_NO_CHANNEL=1; shift ;;
      --slot)
        [ -z "${2:-}" ] && { echo "clrepo: $1 requires a slot number" >&2; return 2; }
        _CLREPO_FORCED_SLOT="$2"; shift 2 ;;
      --status)       _clrepo_slot_status; return ;;
      --free)
        [ -z "${2:-}" ] && { echo "clrepo: $1 requires a slot number" >&2; return 2; }
        _clrepo_slot_free "$2"; echo "clrepo: slot $2 freed"; return ;;
      -D|--delete)    mode_delete=1; shift ;;
      -w|--worktree)
        [ -z "${2:-}" ] && { echo "clrepo: $1 requires a worktree name" >&2; return 2; }
        worktree="$2"; shift 2 ;;
      -h|--help)
        cat <<'EOF'
Usage: clrepo [options] [repo-name]
  -r, --remote          also list uncloned remote repos from discovered forge targets
      --refresh         force refresh of remote cache (implies -r)
  -D, --delete          delete a repo (local and/or remote); with <name> or via picker
  -w, --worktree NAME   pass through to `claude --worktree NAME`
  --slot N                force a specific slot (1..N)
  --no-channel            legacy mode, no slot allocation, no Telegram
  --status                show slot status table
  --free N                force-free slot N (escape hatch)
In picker:
  Enter   launch (cloning first if remote)
  Ctrl-N  create new remote repo (current query becomes seed name)
  Ctrl-D  delete highlighted repo (local and/or remote)
  Ctrl-R  refresh remote cache (only with -r)
SSH persistence: when $SSH_CONNECTION is set, the Claude session is wrapped
in `tmux new-session -A` so disconnecting doesn't kill it. Re-run the same
clrepo command to reattach.
EOF
        return 0 ;;
      --) shift; while [ $# -gt 0 ]; do pos+=("$1"); shift; done ;;
      *) pos+=("$1"); shift ;;
    esac
  done
  set -- "${pos[@]}"

  mkdir -p "$_CLREPO_CACHE"
  local mru="$_CLREPO_CACHE/mru"
  [ -f "$mru" ] || : > "$mru"

  local all
  all=$(find "$_CLREPO_BASE" -type d -name .git -printf '%h\n' 2>/dev/null | sed "s|^$_CLREPO_BASE/||")

  # --delete <name> (non-interactive shortcut): match local repos by basename.
  if [ "$mode_delete" = 1 ] && [ -n "$1" ]; then
    local matches
    matches=$(printf '%s\n' "$all" | grep -Ei "(^|/)$1$")
    if [ -z "$matches" ]; then
      echo "clrepo: no local repo named '$1' (use picker Ctrl-D to delete uncloned remotes)" >&2
      return 1
    fi
    if [ "$(printf '%s\n' "$matches" | wc -l)" -gt 1 ]; then
      echo "clrepo: '$1' is ambiguous:" >&2
      printf '  %s\n' $matches >&2
      return 1
    fi
    _clrepo_delete "$matches"
    return
  fi

  # Positional shortcut: case-insensitive exact-basename lookup, local-only.
  if [ "$mode_delete" = 0 ] && [ -n "$1" ]; then
    local sel
    sel=$(printf '%s\n' "$all" | grep -Ei "(^|/)$1$" | head -1)
    [ -z "$sel" ] && { echo "clrepo: no such repo: $1"; return 1; }
    _clrepo_launch "$sel" "$worktree"
    return
  fi

  # Build local list with MRU on top — this part is fast.
  local listed recent rest
  recent=$(while IFS= read -r line; do
             [ -z "$line" ] && continue
             printf '%s\n' "$all" | grep -qxF "$line" && printf '%s\n' "$line"
           done < "$mru")
  rest=$(printf '%s\n' "$all" | grep -vxF -f <(printf '%s\n' "$recent") 2>/dev/null || printf '%s\n' "$all")
  listed=$(printf '%s\n%s\n' "$recent" "$rest" | awk 'NF')

  local expect="ctrl-n,ctrl-d"
  [ "$with_remote" = 1 ] && expect="$expect,ctrl-r"

  # Stream into fzf: local entries immediately, remote entries as each
  # forge API call returns. The producer dies with SIGPIPE when fzf exits.
  local out query key selraw
  out=$({
    printf '%s\n' "$listed"
    if [ "$with_remote" = 1 ]; then
      _clrepo_remote_list "$force_refresh" 2>/dev/null | while IFS= read -r line; do
        [ -z "$line" ] && continue
        printf '%s\n' "$all" | grep -qxF "$line" || printf '↓ %s\n' "$line"
      done
    fi
  } | fzf --height=40% --reverse --prompt='repo> ' --tiebreak=index \
          --print-query --expect="$expect") || return
  query=$(printf '%s\n' "$out" | sed -n '1p')
  key=$(printf '%s\n' "$out" | sed -n '2p')
  selraw=$(printf '%s\n' "$out" | sed -n '3p')

  case "$key" in
    ctrl-n) _clrepo_create_new "$query"; return ;;
    ctrl-r) clrepo --refresh; return ;;
    ctrl-d)
      [ -z "$selraw" ] && return
      _clrepo_delete "$selraw"
      return ;;
  esac

  [ -z "$selraw" ] && return
  local sel="${selraw#↓ }"
  if [ "$sel" != "$selraw" ]; then
    _clrepo_clone_remote "$sel" || return
  fi
  _clrepo_launch "$sel" "$worktree"
}

_clrepo() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  COMPREPLY=()
  if [[ "$cur" == -* ]]; then
    local flags="-r --remote --refresh -D --delete -w --worktree -h --help"
    COMPREPLY=($(compgen -W "$flags" -- "$cur"))
    return
  fi
  local names
  names=$(find "$_CLREPO_BASE" -type d -name .git -printf '%h\n' 2>/dev/null | xargs -n1 basename)
  shopt -s nocasematch
  local name
  while IFS= read -r name; do
    [[ "$name" == "$cur"* ]] && COMPREPLY+=("$name")
  done <<< "$names"
  shopt -u nocasematch
}
complete -F _clrepo clrepo
