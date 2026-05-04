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

_CLREPO_VERSION="1.15.0"

_CLREPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_CLREPO_BASE="${CLREPO_BASE:-$HOME/projects/repos}"
_CLREPO_CACHE="${CLREPO_CACHE:-$HOME/.cache/clrepo}"
_CLREPO_CONFIG="${CLREPO_CONFIG:-$HOME/.config/clrepo}"
_CLREPO_REMOTE_TTL=600  # seconds
_CLREPO_UPDATE_TTL=86400  # seconds; staleness for latest-version cache
_CLREPO_RAW_URL="https://raw.githubusercontent.com/freaxnx01/config/main/shell/clrepo.sh"

# Autosync function (opt-in commit & push on session close). Same file is
# also exec'd from the tmux session-closed hook in script mode.
[ -f "$_CLREPO_DIR/clrepo-autosync.sh" ] && . "$_CLREPO_DIR/clrepo-autosync.sh"

# User config files (all under $_CLREPO_CONFIG, never committed to the repo):
#   ado-projects  — one ADO project name per line; limits which projects are
#                   listed/cloned. Empty file or absent = no filter (all projects).

# --- Slot / Telegram channel config ---
_CLREPO_MAX_SLOTS="${CLREPO_MAX_SLOTS:-6}"
_CLREPO_SLOTS_FILE="$_CLREPO_CACHE/slots.json"
_CLREPO_SLOTS_LOCK="$_CLREPO_CACHE/slots.lock"
_CLREPO_SLOT_TOKENS="$_CLREPO_CACHE/slot-tokens.json"
_CLREPO_OWNER="$_CLREPO_CACHE/owner.json"

# Presence file at $_CLREPO_CACHE/presence holds one of: auto | away | here.
# Missing or unrecognized → treated as auto.
_CLREPO_PRESENCE_FILE="$_CLREPO_CACHE/presence"

# Yellow-prefixed warning to stderr. Used by _clrepo_sync skip paths.
_clrepo_warn() {
  printf '\033[33mclrepo: %s\033[0m\n' "$*" >&2
}

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
          github/*)
            # Owner-level .envrc shared across public/private (direnv walks parents).
            local o="${rel#github/}"
            [ -d "$_CLREPO_BASE/$rel/public" ] && \
              printf '%s/public\tgithub\t%s\tpublic\n' "$rel" "$o"
            [ -d "$_CLREPO_BASE/$rel/private" ] && \
              printf '%s/private\tgithub\t%s\tprivate\n' "$rel" "$o"
            ;;
          gitlab/*)
            printf '%s\tgitlab\t%s\t-\n' "$rel" "${rel#gitlab/}" ;;
          git-forgejo)
            printf '%s\tforgejo\tfreax\t-\n' "$rel" ;;
          ado)
            printf '%s\tado\tbossinfo\t-\n' "$rel" ;;
        esac
      done
}

# Fetch remote repo names for one target (loaded via direnv in a subshell).
# Emits TSV: <rel_path>\t<description>\t<topics_csv>
# - description: tabs/newlines replaced with spaces; empty if null
# - topics_csv:  comma-separated; empty if none
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
          | jq -r --arg rel "$rel" --arg o "$owner" '
              [ .[] | select(.owner.login == $o) ]
              | sort_by(.name)
              | .[]
              | [ "\($rel)/\(.name)",
                  ((.description // "") | gsub("[\\t\\n\\r]"; " ")),
                  ((.topics // []) | join(",")) ]
              | @tsv
            ' 2>/dev/null
        ;;
      gitlab)
        [ -z "$GITLAB_TOKEN" ] && exit
        curl -sf -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
          "https://gitlab.freaxnx01.ch/api/v4/projects?owned=true&per_page=100" \
          | jq -r --arg rel "$rel" '
              sort_by(.path)
              | .[]
              | [ "\($rel)/\(.path)",
                  ((.description // "") | gsub("[\\t\\n\\r]"; " ")),
                  ((.topics // []) | join(",")) ]
              | @tsv
            ' 2>/dev/null
        ;;
      forgejo)
        [ -z "$FORGEJO_TOKEN" ] && exit
        curl -sf -H "Authorization: token $FORGEJO_TOKEN" \
          "https://git.home.freaxnx01.ch/api/v1/user/repos?limit=50" \
          | jq -r --arg rel "$rel" '
              sort_by(.name)
              | .[]
              | [ "\($rel)/\(.name)",
                  ((.description // "") | gsub("[\\t\\n\\r]"; " ")),
                  ((.topics // []) | join(",")) ]
              | @tsv
            ' 2>/dev/null
        ;;
      ado)
        local tok="${AZURE_DEVOPS_EXT_PAT:-${ADO_PAT:-}}"
        [ -z "$tok" ] && exit
        local _ado_projects_file="$_CLREPO_CONFIG/ado-projects"
        local _ado_allowed="null"
        if [ -f "$_ado_projects_file" ]; then
          _ado_allowed=$(grep -v '^#\|^[[:space:]]*$' "$_ado_projects_file" \
            | jq -Rsc 'split("\n") | map(select(length > 0))')
        fi
        curl -sf -u ":$tok" \
          "https://dev.azure.com/$owner/_apis/git/repositories?api-version=7.1" \
          | jq -r --arg rel "$rel" --argjson allowed "$_ado_allowed" '
              [ .value[]
                | select(
                    $allowed == null or ($allowed | length == 0) or
                    (.project.name as $p | $allowed | index($p) != null)
                  )
              ]
              | sort_by([.project.name, .name])
              | .[]
              | ["\($rel)/\(.project.name)/\(.name)", "", ""]
              | @tsv
            ' 2>/dev/null
        ;;
    esac
  )
}

# Union of remote listings across all targets, cached with TTL.
# Streams per-forge output to stdout (for live fzf) while also writing
# to tmp files that become caches on completion:
#   - remote.list      : plain rel paths (back-compat for the picker stream)
#   - repo-meta.json   : { rel: {description, topics[], fetched_at} }
_clrepo_remote_list() {
  local force="$1"
  local cache="$_CLREPO_CACHE/remote.list"
  local meta_cache="$_CLREPO_CACHE/repo-meta.json"
  local now age
  now=$(date +%s)
  if [ "$force" != 1 ] && [ -f "$cache" ]; then
    age=$(( now - $(stat -c %Y "$cache" 2>/dev/null || echo 0) ))
    if [ "$age" -lt "$_CLREPO_REMOTE_TTL" ]; then
      cat "$cache"; return
    fi
  fi
  echo "clrepo: fetching remote repo listings..." >&2
  local tmp_list tmp_meta
  tmp_list=$(mktemp)
  tmp_meta=$(mktemp)
  echo '{}' > "$tmp_meta"
  _clrepo_targets | while IFS=$'\t' read -r rel forge owner vis; do
    _clrepo_fetch_target "$rel" "$forge" "$owner" "$vis" \
      | while IFS= read -r line; do
          # Split 3-field TSV manually: bash `read` with IFS=$'\t' collapses
          # consecutive tabs (tab is POSIX whitespace), which drops empty fields.
          [ -z "$line" ] && continue
          rpath=${line%%$'\t'*}
          rest=${line#*$'\t'}
          desc=${rest%%$'\t'*}
          topics_csv=${rest#*$'\t'}
          [ -z "$rpath" ] && continue
          # Stream path-only to stdout and remote.list (back-compat)
          printf '%s\n' "$rpath" | tee -a "$tmp_list"
          # Merge into repo-meta.json
          jq --arg k "$rpath" --arg d "$desc" --arg t "$topics_csv" --argjson ts "$now" '
            . + {
              ($k): {
                description: $d,
                topics: ($t | if . == "" then [] else split(",") end),
                fetched_at: $ts
              }
            }
          ' "$tmp_meta" > "$tmp_meta.new" && mv "$tmp_meta.new" "$tmp_meta"
        done
  done
  mv "$tmp_list" "$cache"
  mv "$tmp_meta" "$meta_cache"
}

# Search cached forge metadata (~/.cache/clrepo/repo-meta.json) for a keyword.
# Case-insensitive substring match against each topic and against description.
# Emits TSV: <hit_type>\t<rel_path>\t<snippet>
#   hit_type = "topic" | "desc"
#   snippet  = matched topic name, or a ~50-char window around the desc match
# Topic hits are listed first, then desc hits; each group sorted by basename.
# A repo with both hit types is reported once, as "topic".
_clrepo_meta_search() {
  local kw="$1"
  local meta="$_CLREPO_CACHE/repo-meta.json"
  [ -z "$kw" ] && return 0
  [ -f "$meta" ] || return 0

  jq -r --arg kw "$kw" '
    def ci($s): $s | ascii_downcase;
    def contains_ci($needle; $hay): ci($hay) | contains(ci($needle));
    def snippet($text; $needle):
      (ci($text) | index(ci($needle))) as $i
      | if $i == null then ""
        else
          ([$i - 20, 0] | max) as $s
          | ([$i + ($needle | length) + 20, ($text | length)] | min) as $e
          | ($text[$s:$e])
          | (if $s > 0 then "..." + . else . end)
          | (if $e < ($text | length) then . + "..." else . end)
        end;

    . as $src
    | [ $src | to_entries[]
        | .key as $path
        | (.value.topics // [])
        | map(select(contains_ci($kw; .)))
        | .[]
        | { type: "topic", path: $path, snippet: . }
      ] as $topics
    | ($topics | map(.path)) as $topic_paths
    | [ $src | to_entries[]
        | .key as $path
        | .value as $v
        | select(($topic_paths | any(. == $path)) | not)
        | select(contains_ci($kw; ($v.description // "")))
        | { type: "desc", path: $path,
            snippet: (snippet($v.description; $kw)) }
      ] as $descs
    | ($topics | sort_by(.path | split("/") | last))
      + ($descs | sort_by(.path | split("/") | last))
    | .[]
    | [.type, .path, .snippet] | @tsv
  ' "$meta" 2>/dev/null
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
    ado/*)
      local proj="${parent#ado/}"
      local enc_proj enc_name
      enc_proj=$(printf '%s' "$proj" | jq -sRr '@uri' | tr -d '\n')
      enc_name=$(printf '%s' "$name" | jq -sRr '@uri' | tr -d '\n')
      printf 'https://dev.azure.com/bossinfo/%s/_git/%s\n' "$enc_proj" "$enc_name" ;;
    *) return 1 ;;
  esac
}

# Run `git clone` inside a target dir with direnv loaded, injecting a
# GitHub HTTPS credential helper inline when cloning a github/* target.
_clrepo_git_clone_in() {
  local target="$1" url="$2" name="$3"
  (
    mkdir -p "$_CLREPO_BASE/$target" 2>/dev/null
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
      ado|ado/*)
        local tok="${AZURE_DEVOPS_EXT_PAT:-${ADO_PAT:-}}"
        [ -z "$tok" ] && { echo "clrepo: no ADO_PAT under $target" >&2; exit 1; }
        git \
          -c "credential.https://dev.azure.com.helper=!f() { echo username=x; echo \"password=$tok\"; }; f" \
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
  rm -f "$_CLREPO_CACHE/remote.list" "$_CLREPO_CACHE/repo-meta.json"
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

  local ado_proj=""
  if [ "$forge" = "ado" ]; then
    read -r -p "ADO project: " ado_proj
    [ -z "$ado_proj" ] && { echo "aborted"; return 1; }
  fi

  echo "clrepo: creating $name on $target${ado_proj:+ / $ado_proj}..." >&2
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
      ado)
        local tok="${AZURE_DEVOPS_EXT_PAT:-${ADO_PAT:-}}"
        [ -z "$tok" ] && { echo "ERR: no ADO_PAT under $target" >&2; exit 1; }
        local enc_proj
        enc_proj=$(printf '%s' "$ado_proj" | jq -sRr '@uri' | tr -d '\n')
        local proj_id
        proj_id=$(curl -sf -u ":$tok" \
          "https://dev.azure.com/bossinfo/_apis/projects/$enc_proj?api-version=7.1" \
          | jq -r '.id // empty')
        [ -z "$proj_id" ] && { echo "ERR: project $ado_proj not found" >&2; exit 1; }
        curl -sf -X POST -u ":$tok" \
          -H "Content-Type: application/json" \
          -d "$(jq -cn --arg n "$name" --arg pid "$proj_id" '{name:$n,project:{id:$pid}}')" \
          "https://dev.azure.com/bossinfo/_apis/git/repositories?api-version=7.1" \
          | jq -r '.remoteUrl // empty' ;;
    esac
  )
  [ -z "$url" ] && { echo "clrepo: remote creation failed"; return 1; }

  if [ "$forge" = "ado" ]; then
    target="$target/$ado_proj"
  fi

  echo "clrepo: cloning $url" >&2
  _clrepo_git_clone_in "$target" "$url" "$name" || return 1
  rm -f "$_CLREPO_CACHE/remote.list" "$_CLREPO_CACHE/repo-meta.json"
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
    ado/*)
      forge=ado; owner="${parent#ado/}" ;;
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
        ado)     creds_dir="$_CLREPO_BASE/ado" ;;
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
        ado)
          local tok="${AZURE_DEVOPS_EXT_PAT:-${ADO_PAT:-}}"
          [ -z "$tok" ] && { echo "ERR: no ADO_PAT" >&2; exit 1; }
          local enc_proj enc_name
          enc_proj=$(printf '%s' "$owner" | jq -sRr '@uri' | tr -d '\n')
          enc_name=$(printf '%s' "$name" | jq -sRr '@uri' | tr -d '\n')
          local repo_id
          repo_id=$(curl -sf -u ":$tok" \
            "https://dev.azure.com/bossinfo/$enc_proj/_apis/git/repositories/$enc_name?api-version=7.1" \
            | jq -r '.id // empty')
          [ -z "$repo_id" ] && { echo "ERR: repo lookup failed for $owner/$name" >&2; exit 1; }
          local http_code
          http_code=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE -u ":$tok" \
            "https://dev.azure.com/bossinfo/_apis/git/repositories/$repo_id?api-version=7.1")
          if [ "$http_code" != "204" ]; then
            echo "ERR: ADO DELETE returned HTTP $http_code" >&2
            exit 1
          fi
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

  rm -f "$_CLREPO_CACHE/remote.list" "$_CLREPO_CACHE/repo-meta.json"
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

# Ensure cache dir + slots.json exist. Idempotent; safe to call repeatedly.
# Slot tracking is the default mode — this runs on first launch with no
# user setup required.
_clrepo_slots_init() {
  mkdir -p "$_CLREPO_CACHE" 2>/dev/null
  [ -f "$_CLREPO_SLOTS_FILE" ] || echo '{"slots":{}}' > "$_CLREPO_SLOTS_FILE"
}

# Read slots.json, reconcile PIDs, return JSON on stdout.
_clrepo_slots_read() {
  local f="$_CLREPO_SLOTS_FILE"
  _clrepo_slots_init
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

  # Reconcile dead slots (tmux session is source of truth when recorded;
  # otherwise fall back to PID liveness for foreground-mode records)
  _clrepo_slots_init
  python3 -c "
import json, os, subprocess
f = '$_CLREPO_SLOTS_FILE'
with open(f) as fh: d = json.load(fh)
changed = False
for k, v in list(d.get('slots', {}).items()):
    if not v: continue
    sess = v.get('session') or ''
    if sess:
        alive = subprocess.run(['tmux', 'has-session', '-t', sess],
                               stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL).returncode == 0
    else:
        try: os.kill(int(v.get('pid', 0)), 0); alive = True
        except (ProcessLookupError, ValueError): alive = False
        except PermissionError: alive = True
    if not alive:
        d['slots'][k] = None
        changed = True
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

  # Telegram is opt-in: only warn if slot-tokens.json exists but is missing
  # this slot. With no slot-tokens.json at all, surface a one-time hint
  # pointing to the setup script (gated by a sentinel file).
  if [ -z "$_SLOT_TOKEN" ]; then
    if [ -f "$_CLREPO_SLOT_TOKENS" ]; then
      echo "clrepo: no bot token for slot $_SLOT — Telegram channel disabled for this session." >&2
      echo "  Add slot $_SLOT to $_CLREPO_SLOT_TOKENS to enable." >&2
    elif [ ! -f "$_CLREPO_CACHE/.channels-hinted" ]; then
      echo "clrepo: tip — Telegram pages not configured. Run $_CLREPO_DIR/setup-claude-channels.sh to enable." >&2
      touch "$_CLREPO_CACHE/.channels-hinted" 2>/dev/null
    fi
  fi

  # Wire presence-aware Telegram pages: install per-slot hooks. The watcher
  # is started in _clrepo_slot_record (after slots.json is updated) to avoid
  # racing with the watcher's "no active slots → self-exit" path.
  _clrepo_install_hooks "$_SLOT"
}

# Record slot as busy in slots.json. $5 is the tmux session name (empty
# in foreground mode); when set, reconciliation uses it as the liveness
# signal instead of $pid (which can race or point at a wrapper).
_clrepo_slot_record() {
  local slot="$1" repo="$2" worktree="${3:-}" pid="$4" session="${5:-}"
  exec {_lock_fd}>"$_CLREPO_SLOTS_LOCK"
  flock "$_lock_fd"
  python3 -c "
import json, time
f = '$_CLREPO_SLOTS_FILE'
with open(f) as fh: d = json.load(fh)
d.setdefault('slots', {})['$slot'] = {
    'repo': '$repo', 'worktree': '$worktree' or None,
    'pid': $pid, 'started_at': int(time.time()),
    'session': '$session' or None,
}
with open(f, 'w') as fh: json.dump(d, fh, indent=2)
" 2>/dev/null
  flock -u "$_lock_fd"

  # Start the usage-limit watcher AFTER slots.json is updated so its first
  # poll sees this new slot (otherwise it self-exits during Telegram setup).
  _clrepo_watcher_start
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

  # Clean up presence-page markers for this slot
  rm -f "$_CLREPO_CACHE/sessions/${slot}.idle-since" \
        "$_CLREPO_CACHE/sessions/${slot}.limit-paged" 2>/dev/null
}

# Sanity-check the slot's OAuth credentials before launch so the user sees
# the real cause in clrepo's output (rather than a cryptic "Remote Control
# failed to connect: /login" once Claude is up). Best-effort: any parsing
# error is silent. Args: $1 = slot number.
_clrepo_slot_creds_check() {
  local slot="$1"
  local f="$HOME/.claude-s${slot}/.credentials.json"
  if [ ! -f "$f" ]; then
    _clrepo_warn "slot s${slot} has no credentials, run /login inside Claude after launch"
    return
  fi
  command -v python3 >/dev/null 2>&1 || return 0
  python3 - "$slot" "$f" <<'PY'
import json, sys, time
slot, path = sys.argv[1], sys.argv[2]
try:
    with open(path) as fh: d = json.load(fh)
except Exception:
    print(f"\033[33mclrepo: slot s{slot} credentials unreadable, /login may be required\033[0m", file=sys.stderr)
    sys.exit(0)
oa = d.get('claudeAiOauth') or {}
ea = oa.get('expiresAt') or 0
rt = oa.get('refreshToken') or ''
# expiresAt is milliseconds since epoch; treat smaller magnitudes as seconds defensively.
now_ms = int(time.time() * 1000)
ea_ms = ea if ea > 10**12 else ea * 1000
expired = ea_ms > 0 and ea_ms < now_ms
if expired and not rt:
    print(f"\033[33mclrepo: slot s{slot} access token expired and no refresh token — Remote Control will fail until you /login\033[0m", file=sys.stderr)
PY
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

  local bot_name="#${slot} Claude - ${repo}"
  [ -n "$worktree" ] && bot_name="#${slot} Claude - ${repo} [${worktree}]"
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
    -d "$(printf '{"name":"#%s Claude · idle"}' "$slot")" >/dev/null 2>&1 || true
  curl -sf -X POST "$api/sendMessage" \
    -H "Content-Type: application/json" \
    -d "$(printf '{"chat_id":"%s","text":"🛑 Session s%s closed"}' "$owner_id" "$slot")" >/dev/null 2>&1 || true
  curl -sf -X POST "$api/unpinAllChatMessages" \
    -H "Content-Type: application/json" \
    -d "$(printf '{"chat_id":"%s"}' "$owner_id")" >/dev/null 2>&1 || true
}

# Read the current presence mode. Echoes auto|away|here. Default: auto.
_clrepo_presence_mode() {
  local m
  m=$({ tr -d '[:space:]' < "$_CLREPO_PRESENCE_FILE"; } 2>/dev/null)
  case "$m" in
    auto|away|here) printf '%s' "$m" ;;
    *)              printf 'auto' ;;
  esac
}

# Set presence mode. $1 must be auto|away|here. Prints a one-line confirmation.
_clrepo_presence_set() {
  local mode="$1"
  case "$mode" in
    auto|away|here) ;;
    *) echo "clrepo: invalid presence mode '$mode' (expected auto|away|here)" >&2; return 2 ;;
  esac
  mkdir -p "$_CLREPO_CACHE"
  printf '%s\n' "$mode" > "$_CLREPO_PRESENCE_FILE"
  echo "clrepo: presence set to '$mode'"
}

# Print current presence mode and per-slot effective state.
_clrepo_presence_show() {
  local mode
  mode=$(_clrepo_presence_mode)
  echo "presence mode: $mode"
  [ -f "$_CLREPO_SLOTS_FILE" ] || { echo "(no slots configured)"; return; }
  python3 -c "
import json, subprocess
with open('$_CLREPO_SLOTS_FILE') as f: d = json.load(f)
mode = '$mode'
for n in sorted(d.get('slots', {}).keys(), key=int):
    v = d['slots'][n]
    if not v:
        print(f's{n}: free')
        continue
    sess = v.get('session') or ''
    if mode == 'away':
        eff = 'away (forced)'
    elif mode == 'here':
        eff = 'present (forced)'
    elif sess:
        r = subprocess.run(['tmux','list-clients','-t',sess],
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        n_clients = len([l for l in r.stdout.decode().splitlines() if l.strip()])
        eff = 'present' if n_clients > 0 else 'away'
    else:
        eff = 'unknown (no session recorded)'
    print(f's{n}: {eff}  (repo={v.get(\"repo\",\"?\")}, session={sess or \"—\"})')
" 2>/dev/null
}

# Decide whether slot $1 should send a Telegram page right now.
# Returns 0 (page) or 1 (silent).
_clrepo_should_page() {
  local slot="$1"
  local mode
  mode=$(_clrepo_presence_mode)
  case "$mode" in
    away) return 0 ;;
    here) return 1 ;;
    auto)
      # Look up the slot's tmux session name from slots.json
      local sess
      sess=$(python3 -c "
import json
try:
    with open('$_CLREPO_SLOTS_FILE') as f: d = json.load(f)
    v = d.get('slots', {}).get('$slot')
    print((v or {}).get('session') or '')
except Exception:
    pass
" 2>/dev/null)
      # No recorded session → assume away (page); we'd rather notify than miss
      [ -z "$sess" ] && return 0
      # Dead session → page (slots.json wasn't reconciled yet)
      tmux has-session -t "$sess" 2>/dev/null || return 0
      # Live session — count attached clients
      local n
      n=$(tmux list-clients -t "$sess" 2>/dev/null | wc -l)
      [ "$n" -eq 0 ] && return 0 || return 1
      ;;
  esac
}

# Send arbitrary text via slot $1's bot to the configured owner.
# Args: $1 = slot, $2 = message text. Best-effort; never fails the caller.
# Reads the slot bot token from Passbolt via slot-tokens.json, owner from owner.json.
_clrepo_telegram_page() {
  local slot="$1" text="$2"
  [ -z "$slot" ] && return 0
  [ -z "$text" ] && return 0

  local pb_id token owner_id
  pb_id=$(python3 -c "
import json
try:
    with open('$_CLREPO_SLOT_TOKENS') as f: d = json.load(f)
    print(d.get('$slot', ''))
except Exception:
    pass
" 2>/dev/null)
  [ -z "$pb_id" ] && return 0

  token=$(passbolt get resource --id "$pb_id" 2>/dev/null | awk -F": " '/^Password:/ {print $2}')
  [ -z "$token" ] && return 0

  owner_id=$(python3 -c "
import json
try:
    with open('$_CLREPO_OWNER') as f: d = json.load(f)
    print(d.get('telegram_user_id', ''))
except Exception:
    pass
" 2>/dev/null)
  [ -z "$owner_id" ] && return 0

  curl -sf -X POST "https://api.telegram.org/bot${token}/sendMessage" \
    -H "Content-Type: application/json" \
    -d "$(python3 -c "import json,sys; print(json.dumps({'chat_id': '$owner_id', 'text': sys.stdin.read()}))" <<< "$text")" \
    >/dev/null 2>&1 || true
}

# Idempotently merge the Notification + UserPromptSubmit hooks into slot $1's
# settings.json (~/.claude-s<N>/settings.json). The hook commands include the
# slot number as a positional arg so the hook scripts know which slot fired.
_clrepo_install_hooks() {
  local slot="$1"
  [ -z "$slot" ] && return 1
  local cfg_dir="$HOME/.claude-s${slot}"
  local cfg="$cfg_dir/settings.json"
  local notify="$_CLREPO_DIR/clrepo-hooks/notify.sh"
  local clear="$_CLREPO_DIR/clrepo-hooks/clear-idle.sh"

  [ -x "$notify" ] || chmod +x "$notify" 2>/dev/null
  [ -x "$clear" ]  || chmod +x "$clear"  2>/dev/null

  mkdir -p "$cfg_dir" "$_CLREPO_CACHE"
  exec {_lock_fd}>"$_CLREPO_CACHE/hooks.lock"
  flock "$_lock_fd"
  python3 -c "
import json, os
cfg = '$cfg'
notify_cmd = '$notify $slot'
clear_cmd  = '$clear $slot'

try:
    with open(cfg) as f: d = json.load(f)
except FileNotFoundError:
    d = {}
except json.JSONDecodeError:
    # Corrupt — back up and start fresh
    os.rename(cfg, cfg + '.corrupt')
    d = {}

hooks = d.setdefault('hooks', {})

def has_cmd(entries, cmd):
    for e in entries or []:
        for h in e.get('hooks', []) or []:
            if h.get('command') == cmd: return True
    return False

def add_cmd(key, cmd):
    entries = hooks.setdefault(key, [])
    if has_cmd(entries, cmd): return
    entries.append({'matcher': '', 'hooks': [{'type': 'command', 'command': cmd}]})

add_cmd('Notification',      notify_cmd)
add_cmd('UserPromptSubmit',  clear_cmd)

with open(cfg, 'w') as f: json.dump(d, f, indent=2)
" 2>/dev/null
  flock -u "$_lock_fd"
}

# Start the usage-limit watcher daemon if not already running. Idempotent.
_clrepo_watcher_start() {
  local pid_file="$_CLREPO_CACHE/watcher.pid"
  if [ -f "$pid_file" ]; then
    if kill -0 "$(cat "$pid_file")" 2>/dev/null; then
      return 0  # already running
    fi
  fi
  local watcher="$_CLREPO_DIR/clrepo-watcher.sh"
  [ -x "$watcher" ] || chmod +x "$watcher" 2>/dev/null
  ( setsid "$watcher" </dev/null >/dev/null 2>&1 & ) 2>/dev/null
  return 0
}

# Print slot status table.
_clrepo_slot_status() {
  _clrepo_slots_init

  # Reconcile dead slots (tmux session is source of truth when recorded;
  # otherwise fall back to PID liveness for foreground-mode records)
  python3 -c "
import json, os, subprocess
f = '$_CLREPO_SLOTS_FILE'
MAX = $_CLREPO_MAX_SLOTS
with open(f) as fh: d = json.load(fh)
slots = d.setdefault('slots', {})
for k, v in list(slots.items()):
    if not v: continue
    sess = v.get('session') or ''
    if sess:
        alive = subprocess.run(['tmux', 'has-session', '-t', sess],
                               stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL).returncode == 0
    else:
        try: os.kill(int(v.get('pid', 0)), 0); alive = True
        except (ProcessLookupError, ValueError): alive = False
        except PermissionError: alive = True
    if not alive:
        slots[k] = None
# Drop empty entries whose key isn't a valid slot number (non-numeric, negative,
# or > MAX_SLOTS) — leftover from manual edits or shrunk MAX. Live entries are
# preserved so we never orphan a running session's record.
for k in list(slots.keys()):
    if slots[k] is not None: continue
    try: n = int(k)
    except ValueError: del slots[k]; continue
    if n < 0 or n > MAX: del slots[k]
with open(f, 'w') as fh: json.dump(d, fh, indent=2)
" 2>/dev/null

  python3 -c "
import json, time
with open('$_CLREPO_SLOTS_FILE') as f: d = json.load(f)
tokens = {}
try:
    with open('$_CLREPO_SLOT_TOKENS') as f: tokens = json.load(f)
except: pass
slots = d.get('slots', {})
MAX = $_CLREPO_MAX_SLOTS
keys = set(slots.keys()) | set(tokens.keys()) | {str(n) for n in range(1, MAX + 1)}
# Drop non-numeric / out-of-range keys defensively, in case stale entries
# slipped past reconcile (live records aren't pruned there).
keys = {k for k in keys if k.isdigit() and 0 <= int(k) <= MAX}
now = int(time.time())
print(f\"{'SLOT':<5} {'REPO':<30} {'WORKTREE':<15} {'STARTED':<20} {'PID':<8} {'BOT'}\")
print('-' * 95)
for n in sorted(keys, key=int):
    v = slots.get(n)
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

_clrepo_print_last() {
  local f="$_CLREPO_CACHE/last"
  [ -f "$f" ] || return
  printf 'clrepo: path:   %s\n' "$(sed -n '1p' "$f")" >&2
  printf 'clrepo: remote: %s\n' "$(sed -n '2p' "$f")" >&2
}

# Derive a stable tmux session name from repo basename + optional worktree.
# Identical for a given (repo, worktree) pair so reattach checks match
# session creates.
_clrepo_tmux_session_name() {
  local s="$1"
  [ -n "${2:-}" ] && s="$1-$2"
  printf '%s' "${s//[^A-Za-z0-9_-]/_}"
}

# Fast-forward sync of the current branch with its upstream before launch.
# Args: $1 = repo basename, $2 = optional worktree name.
# Never fails the launch; every error path returns 0 after a stderr line.
_clrepo_sync() {
  local repo="$1" worktree="${2:-}"
  [ "${_CLREPO_NO_SYNC:-0}" = 1 ] && return 0

  # Skip if we're about to reattach an existing tmux session.
  if [ -n "${SSH_CONNECTION:-}" ] && command -v tmux >/dev/null; then
    local session
    session=$(_clrepo_tmux_session_name "$repo" "$worktree")
    tmux has-session -t "$session" 2>/dev/null && return 0
  fi

  local branch upstream
  branch=$(git symbolic-ref --quiet --short HEAD) || {
    _clrepo_warn "detached HEAD, skipping sync"; return 0; }
  upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) || {
    _clrepo_warn "no upstream for $branch, skipping sync"; return 0; }
  if ! git diff --quiet || ! git diff --cached --quiet; then
    _clrepo_warn "dirty working tree, skipping sync"; return 0
  fi

  timeout 10 git fetch --quiet 2>/dev/null || {
    _clrepo_warn "fetch failed or timed out, skipping sync"; return 0; }

  local local_sha upstream_sha base
  local_sha=$(git rev-parse HEAD)
  upstream_sha=$(git rev-parse '@{u}')
  [ "$local_sha" = "$upstream_sha" ] && return 0

  base=$(git merge-base HEAD '@{u}')
  if [ "$base" = "$upstream_sha" ]; then
    return 0  # local is ahead of upstream — fine, nothing to pull
  elif [ "$base" = "$local_sha" ]; then
    git merge --ff-only --quiet '@{u}' || {
      _clrepo_warn "ff-only merge failed unexpectedly, skipping sync"; return 0; }
    printf 'clrepo: pulled %s..%s on %s\n' \
      "$(git rev-parse --short "$local_sha")" \
      "$(git rev-parse --short "$upstream_sha")" "$branch" >&2
  else
    _clrepo_warn "$branch diverged from $upstream, skipping sync"
  fi
}

_clrepo_launch() {
  local sel="$1"
  local worktree="${2:-}"
  local editor="${3:-}"
  local remote_control="${4:-1}"
  local mru="$_CLREPO_CACHE/mru"
  cd "$_CLREPO_BASE/$sel" || return
  _clrepo_sync "$(basename "$sel")" "$worktree"
  { printf '%s
' "$sel"; grep -vxF "$sel" "$mru" 2>/dev/null; } | head -10 > "$mru.tmp" && mv "$mru.tmp" "$mru"

  local repo display_name
  repo=$(basename "$sel")
  # Distinguish worktree sessions in `-n` so the prompt box, terminal title,
  # and /resume picker can tell `repo` and `repo -w doc` apart. Matches the
  # Telegram bot title format set in _clrepo_telegram_setup.
  display_name="$repo"
  [ -n "$worktree" ] && display_name="$repo [$worktree]"

  local _remote_url _session_path
  _remote_url=$(git remote get-url origin 2>/dev/null || echo '(no remote)')
  # `claude --worktree NAME` runs in <repo>/.claude/worktrees/<NAME>/, so
  # record that path (not the main repo) for `path:` and downstream readers.
  # Copilot mode rewrites this further down after cd'ing into the git worktree.
  _session_path="$PWD"
  if [ -n "$worktree" ] && [ -z "$editor" ]; then
    _session_path="$PWD/.claude/worktrees/$worktree"
  fi
  printf '%s\n%s\n' "$_session_path" "$_remote_url" > "$_CLREPO_CACHE/last"

  # VS Code mode — open directory, skip slot/Telegram/tmux entirely
  if [ "$editor" = "code" ]; then
    code .
    _clrepo_print_last
    return
  fi

  # Copilot mode — run `copilot --yolo`. Honors -w by cd'ing into the matching
  # git worktree (lookup by basename in `git worktree list`). Skips slot/Telegram
  # but keeps the tmux SSH wrap so disconnects don't kill the session.
  if [ "$editor" = "copilot" ]; then
    if [ -n "$worktree" ]; then
      local wt_path=""
      while IFS= read -r p; do
        [ "$(basename "$p")" = "$worktree" ] && { wt_path="$p"; break; }
      done < <(git worktree list --porcelain 2>/dev/null | awk '/^worktree / {print $2}')
      if [ -z "$wt_path" ]; then
        echo "clrepo: no worktree named '$worktree' under $sel" >&2
        return 1
      fi
      cd "$wt_path" || return 1
      printf '%s\n%s\n' "$PWD" "$_remote_url" > "$_CLREPO_CACHE/last"
    fi
    if [ -n "${SSH_CONNECTION:-}" ] && command -v tmux >/dev/null; then
      local session
      session=$(_clrepo_tmux_session_name "$repo" "$worktree")
      tmux new-session -A -s "$session" copilot --yolo
    else
      copilot --yolo
    fi
    _clrepo_print_last
    return
  fi

  # --- Slot allocation (skip only with explicit --no-channel) ---
  if [ "${_CLREPO_NO_CHANNEL:-0}" = 1 ]; then
    # User opted out: no slot, no Telegram, shared CLAUDE_CONFIG_DIR (~/.claude).
    echo "clrepo: --no-channel set: no slot, no Telegram, shared ~/.claude." >&2
    local -a claude_args=(-n "$display_name")
    [ -n "$worktree" ] && claude_args+=(--worktree "$worktree")
    [ "$remote_control" = 1 ] && claude_args+=(--remote-control)
    if [ -n "${SSH_CONNECTION:-}" ] && command -v tmux >/dev/null; then
      local session
      session=$(_clrepo_tmux_session_name "$repo" "$worktree")
      tmux new-session -A -s "$session" claude "${claude_args[@]}"
    else
      claude "${claude_args[@]}"
    fi
    _clrepo_print_last
    return
  fi

  # Allocate a slot (auto-inits slots.json on first use)
  _clrepo_slot_allocate "${_CLREPO_FORCED_SLOT:-}" || return

  local -a claude_args=(-n "$display_name" --dangerously-skip-permissions --channels plugin:telegram@claude-plugins-official)
  [ -n "$worktree" ] && claude_args+=(--worktree "$worktree")
  [ "$remote_control" = 1 ] && claude_args+=(--remote-control)

  export CLAUDE_CONFIG_DIR="$HOME/.claude-s${_SLOT}"
  export TELEGRAM_BOT_TOKEN="$_SLOT_TOKEN"

  echo "clrepo: using slot s${_SLOT} (CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR)" >&2
  _clrepo_slot_creds_check "$_SLOT"

  if [ -n "${SSH_CONNECTION:-}" ] && command -v tmux >/dev/null; then
    local session
    session=$(_clrepo_tmux_session_name "$repo" "$worktree")

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
    # Keep the pane visible on non-zero exit so the user actually sees claude's
    # startup error on attach instead of just `[exited]`. Auto-close on exit 0
    # so the success path stays clean (no dangling pane to dismiss).
    tmux set-option -t "$session" remain-on-exit on
    tmux set-hook   -t "$session" pane-died       "if-shell -F '#{==:#{pane_dead_status},0}' 'kill-pane'"
    # Record repo path so the session-closed hook can find it for autosync.
    mkdir -p "$_CLREPO_CACHE/sessions"
    printf '%s\n' "$PWD" > "$_CLREPO_CACHE/sessions/${session}.path"
    tmux set-hook -t "$session" session-closed "run-shell '$_CLREPO_DIR/clrepo-autosync.sh $session $_SLOT_TOKEN; $HOME/.cache/clrepo/cleanup.sh $_SLOT $_SLOT_TOKEN'"

    local pid
    pid=$(tmux display-message -t "$session" -p '#{pane_pid}' 2>/dev/null || echo 0)
    _clrepo_slot_record "$_SLOT" "$repo" "$worktree" "$pid" "$session"
    tmux attach-session -t "$session"

    # Failure path: claude exited non-zero, pane stayed (via remain-on-exit)
    # so the user could read the error. After they detach, reap the lingering
    # session, tell them clrepo registered the failure, and skip print_last
    # (the path/remote on disk is for a session that never really started).
    if tmux has-session -t "$session" 2>/dev/null; then
      local _live
      _live=$(tmux list-panes -t "$session" -F '#{pane_dead}' 2>/dev/null | grep -c '^0$')
      if [ "$_live" = "0" ]; then
        tmux kill-session -t "$session" 2>/dev/null
        echo "clrepo: claude exited unexpectedly — see error above" >&2
        return 1
      fi
    fi

    _clrepo_print_last
    # On detach: slot stays allocated (claude is still running in tmux).
    # PID reconciliation will free it when claude actually exits.
  else
    # Foreground mode — cleanup on exit
    _clrepo_telegram_setup "$_SLOT" "$repo" "$worktree" "$_SLOT_TOKEN"
    _clrepo_slot_record "$_SLOT" "$repo" "$worktree" "$$"
    claude "${claude_args[@]}"
    command -v _clrepo_autosync >/dev/null && _clrepo_autosync "$PWD" "$_SLOT_TOKEN"
    _clrepo_slot_free "$_SLOT"
    _clrepo_telegram_cleanup "$_SLOT" "$_SLOT_TOKEN"
    _clrepo_print_last
  fi
}

# Return 0 if $1 is a strictly higher semver than $2 (using `sort -V`).
_clrepo_version_gt() {
  [ "$1" = "$2" ] && return 1
  local higher
  higher=$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)
  [ "$higher" = "$1" ]
}

# Hint if a newer _CLREPO_VERSION is available. Local-first: check the
# on-disk clrepo.sh that this shell was sourced from (kept current with
# origin by _clrepo_autosync). Fall back to a TTL-gated remote curl only
# when the on-disk path can't be resolved or read.
_clrepo_check_latest() {
  local script="${BASH_SOURCE[0]}"
  if command -v readlink >/dev/null 2>&1; then
    script=$(readlink -f "$script" 2>/dev/null || echo "$script")
  fi

  if [ -r "$script" ]; then
    local on_disk
    on_disk=$(grep -m1 '^_CLREPO_VERSION=' "$script" 2>/dev/null \
              | sed -E 's/^_CLREPO_VERSION="?([^"]+)"?.*/\1/')
    if [ -n "$on_disk" ]; then
      if _clrepo_version_gt "$on_disk" "$_CLREPO_VERSION"; then
        echo "clrepo: new version $on_disk available (you have $_CLREPO_VERSION) — run \`clrepo update\`" >&2
      fi
      return 0
    fi
  fi

  # Fallback: on-disk path missing/unreadable/malformed. Use the cached
  # remote check (background-refresh, mtime-gated by TTL).
  local cache="$_CLREPO_CACHE/latest-version"
  local age
  age=$(( $(date +%s) - $(stat -c %Y "$cache" 2>/dev/null || echo 0) ))
  if [ ! -f "$cache" ] || [ "$age" -gt "$_CLREPO_UPDATE_TTL" ]; then
    (
      flock -n 9 || exit 0
      local v
      v=$(curl -fsSL --max-time 5 "$_CLREPO_RAW_URL" 2>/dev/null \
            | grep -m1 '^_CLREPO_VERSION=' \
            | sed -E 's/^_CLREPO_VERSION="?([^"]+)"?.*/\1/')
      [ -n "$v" ] && printf '%s\n' "$v" > "$cache"
    ) 9>"$_CLREPO_CACHE/latest-warm.lock" </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null || true
  fi
  [ -f "$cache" ] || return 0
  local latest
  latest=$(cat "$cache" 2>/dev/null)
  [ -z "$latest" ] && return 0
  if _clrepo_version_gt "$latest" "$_CLREPO_VERSION"; then
    echo "clrepo: new version $latest available (you have $_CLREPO_VERSION) — run \`clrepo update\`" >&2
  fi
}

# Pull the config repo that hosts clrepo.sh, then re-source the script
# in the calling shell so the new function bodies take effect immediately.
_clrepo_update() {
  local script="${BASH_SOURCE[0]}"
  if command -v readlink >/dev/null 2>&1; then
    script=$(readlink -f "$script" 2>/dev/null || echo "$script")
  fi
  local root
  root=$(git -C "$(dirname "$script")" rev-parse --show-toplevel 2>/dev/null) || {
    echo "clrepo: cannot locate config repo (script: $script)" >&2
    return 1
  }
  echo "clrepo: pulling $root"
  local old_ver="$_CLREPO_VERSION"
  if ! git -C "$root" pull --ff-only; then
    echo "clrepo: git pull failed (resolve manually in $root)" >&2
    return 1
  fi
  # Disable alias expansion during re-source: an interactive shell may have
  # `alias clrepo='clrepo ...'`, which bash would expand inline at parse time
  # and break the `clrepo() {` definition.
  local _ea=0
  shopt -q expand_aliases && _ea=1
  shopt -u expand_aliases
  # shellcheck disable=SC1090
  . "$script"
  [ "$_ea" = 1 ] && shopt -s expand_aliases
  printf '%s\n' "$_CLREPO_VERSION" > "$_CLREPO_CACHE/latest-version" 2>/dev/null
  if [ "$old_ver" = "$_CLREPO_VERSION" ]; then
    echo "clrepo: already at $_CLREPO_VERSION"
  else
    echo "clrepo: updated $old_ver → $_CLREPO_VERSION"
  fi
}

clrepo() {
  local with_remote=0 force_refresh=0 mode_delete=0 worktree="" editor="" remote_control=1 _CLREPO_NO_CHANNEL=0 _CLREPO_FORCED_SLOT="" _CLREPO_NO_SYNC=0
  local -a pos=()
  while [ $# -gt 0 ]; do
    case "$1" in
      -r|--remote)    with_remote=1; shift ;;
      --refresh)      with_remote=1; force_refresh=1; shift ;;
      --no-channel)   _CLREPO_NO_CHANNEL=1; shift ;;
      --no-sync)      _CLREPO_NO_SYNC=1; shift ;;
      --slot)
        [ -z "${2:-}" ] && { echo "clrepo: $1 requires a slot number" >&2; return 2; }
        _CLREPO_FORCED_SLOT="$2"; shift 2 ;;
      --status)       _clrepo_slot_status; return ;;
      --free)
        [ -z "${2:-}" ] && { echo "clrepo: $1 requires a slot number" >&2; return 2; }
        _clrepo_slot_free "$2"; echo "clrepo: slot $2 freed"; return ;;
      -D|--delete)    mode_delete=1; shift ;;
      -c|--code)      editor=code; shift ;;
      -p|--copilot)   editor=copilot; shift ;;
      --remote-control|--rc) remote_control=1; shift ;;
      --no-remote-control|--no-rc) remote_control=0; shift ;;
      -w|--worktree)
        [ -z "${2:-}" ] && { echo "clrepo: $1 requires a worktree name" >&2; return 2; }
        worktree="$2"; shift 2 ;;
      -V|--version)
        echo "clrepo $_CLREPO_VERSION"; return 0 ;;
      -h|--help)
        cat <<'EOF'
Usage: clrepo [options] [repo-name|.|update|away|back|here|presence]
  (no args)             launch current repo if CWD is under $CLREPO_BASE, else picker
  .                     launch current repo (errors if CWD is not inside a known repo)
  update                git pull the config repo hosting clrepo.sh and re-source it
  away                  set presence to "away" (Telegram pages enabled for all slots)
  back                  resume auto-detection (per-slot tmux client check)
  here                  set presence to "here" (Telegram pages disabled for all slots)
  presence              show current presence mode and per-slot effective state
  -r, --remote          also list uncloned remote repos from discovered forge targets
      --refresh         force refresh of remote cache (implies -r)
  -D, --delete          delete a repo (local and/or remote); with <name> or via picker
  -c, --code            open repo in VS Code instead of Claude Code CLI
  -p, --copilot         launch `copilot --yolo` instead of Claude Code CLI
      --remote-control, --rc
                        pass `--remote-control` to claude (steer session from
                        claude.ai/code or mobile app); on by default, requires
                        claude.ai OAuth login. Ignored with -c and -p.
      --no-remote-control, --no-rc
                        opt out of `--remote-control` for this launch.
  -w, --worktree NAME   pass through to `claude --worktree NAME`
                        with -p: cd into the matching git worktree first
  -V, --version         print version and exit
  --slot N              force a specific slot (1..N)
  --no-channel          legacy mode, no slot allocation, no Telegram
  --no-sync             skip the upstream fast-forward pull on startup
  --status              show slot status table
  --free N              force-free slot N (escape hatch)
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

  # `clrepo update` — pull the config repo and re-source. Handled before the
  # update hint and meta-warm so we don't nag the user during an update.
  if [ "${1:-}" = "update" ]; then
    _clrepo_update
    return
  fi

  # Presence sub-commands. Handled here (before the launch path) so they
  # work from any cwd, regardless of repo membership.
  case "${1:-}" in
    away)     _clrepo_presence_set away; return ;;
    back)     _clrepo_presence_set auto; return ;;
    here)     _clrepo_presence_set here; return ;;
    presence) _clrepo_presence_show;     return ;;
  esac

  _clrepo_check_latest

  # Background-warm repo-meta.json so tab-completion keyword search works
  # without an explicit `-r`/`--refresh` first. Skipped when -r is set (the
  # picker does it synchronously). flock prevents pile-ups across shells.
  if [ "$with_remote" = 0 ]; then
    local _meta="$_CLREPO_CACHE/repo-meta.json" _age
    _age=$(( $(date +%s) - $(stat -c %Y "$_meta" 2>/dev/null || echo 0) ))
    if [ ! -f "$_meta" ] || [ "$_age" -gt "$_CLREPO_REMOTE_TTL" ]; then
      (
        flock -n 9 || exit 0
        _clrepo_remote_list 0 >/dev/null 2>&1
      ) 9>"$_CLREPO_CACHE/meta-warm.lock" </dev/null >/dev/null 2>&1 &
      disown 2>/dev/null || true
    fi
  fi

  # Launch current repo when invoked with "." or bare from inside a repo.
  # Skip when -r/--remote/--refresh is set: user explicitly wants the picker.
  if [ "$mode_delete" = 0 ] && [ "$with_remote" = 0 ] && { [ "${1:-}" = "." ] || [ $# -eq 0 ]; }; then
    local git_root=""
    git_root=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)
    if [ -n "$git_root" ] && [ "${git_root#$_CLREPO_BASE/}" != "$git_root" ]; then
      _clrepo_launch "${git_root#$_CLREPO_BASE/}" "$worktree" "$editor" "$remote_control"
      return
    fi
    if [ "${1:-}" = "." ]; then
      echo "clrepo: '.' requires current dir to be inside a repo under $_CLREPO_BASE" >&2
      return 1
    fi
  fi

  local all
  all=$(find "$_CLREPO_BASE" -type d -name '_archive' -prune -o -type d -name .git -printf '%h\n' 2>/dev/null | sed "s|^$_CLREPO_BASE/||")

  # --delete <name> (non-interactive shortcut): match local repos by basename.
  if [ "$mode_delete" = 1 ] && [ -n "${1:-}" ]; then
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

  # Positional shortcut: case-insensitive basename lookup (exact, then substring).
  # If name misses, fall back to metadata (topics + description) search.
  if [ "$mode_delete" = 0 ] && [ -n "${1:-}" ]; then
    local sel
    sel=$(printf '%s\n' "$all" | grep -Ei "(^|/)$1$" | head -1)
    [ -z "$sel" ] && sel=$(printf '%s\n' "$all" | grep -Ei "(^|/)[^/]*$1[^/]*$" | head -1)
    if [ -n "$sel" ]; then
      _clrepo_launch "$sel" "$worktree" "$editor" "$remote_control"
      return
    fi

    # Name miss — try metadata search.
    local meta_hits count hit_path was_remote=0
    meta_hits=$(_clrepo_meta_search "$1")
    count=$(printf '%s' "$meta_hits" | grep -c '^' 2>/dev/null); count=${count:-0}

    if [ "$count" = 0 ]; then
      echo "clrepo: no such repo: $1" >&2
      return 1
    fi

    if [ "$count" = 1 ]; then
      hit_path=$(printf '%s' "$meta_hits" | cut -f2)
      printf '%s\n' "$all" | grep -qxF "$hit_path" || was_remote=1
      if [ "$was_remote" = 1 ]; then
        _clrepo_clone_remote "$hit_path" || return 1
      fi
      _clrepo_launch "$hit_path" "$worktree" "$editor" "$remote_control"
      return
    fi

    # 2+ hits — annotated fzf picker. Carry the raw path as a trailing
    # tab-separated field so extraction is exact, regardless of any
    # whitespace in the formatted display column.
    local pick
    pick=$(printf '%s\n' "$meta_hits" \
      | awk -F'\t' 'BEGIN{OFS="\t"} { printf "%-50s  [%s: %s]\t%s\n", $2, $1, $3, $2 }' \
      | fzf --height=40% --reverse --prompt="match '$1'> " -d $'\t' --with-nth=1) || return
    hit_path=$(printf '%s' "$pick" | awk -F'\t' '{print $2}')
    [ -z "$hit_path" ] && return
    printf '%s\n' "$all" | grep -qxF "$hit_path" || was_remote=1
    if [ "$was_remote" = 1 ]; then
      _clrepo_clone_remote "$hit_path" || return 1
    fi
    _clrepo_launch "$hit_path" "$worktree" "$editor" "$remote_control"
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
  _clrepo_launch "$sel" "$worktree" "$editor" "$remote_control"
}

_clrepo() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  COMPREPLY=()
  if [[ "$cur" == -* ]]; then
    local flags="-r --remote --refresh -D --delete -c --code -p --copilot --remote-control --rc -w --worktree --no-sync --no-channel --slot --status --free -V --version -h --help"
    COMPREPLY=($(compgen -W "$flags" -- "$cur"))
    return
  fi
  local names name
  names=$(find "$_CLREPO_BASE" -type d -name '_archive' -prune -o -type d -name .git -printf '%h\n' 2>/dev/null | xargs -n1 basename)
  shopt -s nocasematch
  while IFS= read -r name; do
    [[ "$name" == *"$cur"* ]] && COMPREPLY+=("$name")
  done <<< "$names"
  # Built-in verbs
  for verb in update away back here presence; do
    [[ "$verb" == *"$cur"* ]] && COMPREPLY+=("$verb")
  done
  shopt -u nocasematch

  # Keyword fallback: when cur is non-empty, also include basenames of repos
  # whose cached topics/description match (mirrors positional-arg behavior).
  if [ -n "$cur" ] && [ -f "$_CLREPO_CACHE/repo-meta.json" ]; then
    local meta_names found c
    meta_names=$(_clrepo_meta_search "$cur" 2>/dev/null | awk -F'\t' '{print $2}' | awk -F/ '{print $NF}')
    while IFS= read -r name; do
      [ -z "$name" ] && continue
      found=0
      for c in "${COMPREPLY[@]}"; do [ "$c" = "$name" ] && { found=1; break; }; done
      [ "$found" = 0 ] && COMPREPLY+=("$name")
    done <<< "$meta_names"
  fi
}
complete -F _clrepo clrepo
