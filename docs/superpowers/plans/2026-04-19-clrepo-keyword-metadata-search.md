# clrepo Keyword Metadata Search — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `clrepo <keyword>` to fall back to searching cached forge metadata (topics + description) when the keyword doesn't match a local repo name.

**Architecture:** Reuse the forge API calls already made by `_clrepo_fetch_target` (GitHub/GitLab/Forgejo `list repos` endpoints already return topics + description). Persist them to `~/.cache/clrepo/repo-meta.json` alongside the existing `remote.list`. A new `_clrepo_meta_search` helper reads that cache and returns matches classified by hit type (topic vs. description). The fallback hooks into the positional-arg branch of `clrepo()` after the existing name-match miss.

**Tech Stack:** Bash, `jq` (already required), `fzf` (already used), `curl` (already used). No new dependencies.

**Repo:** `freaxnx01/config` (the shell-config repo used across claude-dev LXC, WSL2 on Win11, and the company notebook).

**Testing note:** The repo has no test harness. Verification is by running commands and inspecting output. Each task ends with a concrete verification step showing expected behavior.

---

## File Structure

**Modified files:**
- `shell/clrepo.sh` — all code changes live here (single file, ~856 lines today):
  - `_clrepo_fetch_target` (line 58): also emit description + topics on each line.
  - `_clrepo_remote_list` (line 92): write `repo-meta.json` in the same pass it writes `remote.list`.
  - New function `_clrepo_meta_search`: read `repo-meta.json`, return matches.
  - `clrepo()` positional branch (line ~795): add metadata fallback after name miss.
  - `clrepo --refresh` path: also invalidates `repo-meta.json`.
- `shell/CLREPO.md` — user-facing cheat sheet update.

**New files:**
- None. Cache file `~/.cache/clrepo/repo-meta.json` is created at runtime.

---

## Task 1: Capture topics + description in the forge listing

**Why:** All three forge APIs already return topics and description in their bulk listing responses. The existing `_clrepo_fetch_target` discards those fields and only keeps `name`. Widen its output so downstream code can cache the metadata.

**Files:**
- Modify: `shell/clrepo.sh:58-89` (function `_clrepo_fetch_target`)

**Design decision — output format:**
Widen the stream from a single path-per-line to TSV: `<rel_path>\t<description>\t<topics_csv>`.
- `description`: stripped of tabs/newlines (replaced with spaces), empty string if null.
- `topics_csv`: comma-separated, empty string if none.

This keeps the stream-to-fzf pipeline in `_clrepo_remote_list` working by continuing to feed path-per-line to fzf (first TSV column), while the metadata is captured in parallel.

- [ ] **Step 1: Replace `_clrepo_fetch_target` body**

Replace lines 58-89 of `shell/clrepo.sh` with:

```bash
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
              .[]
              | select(.owner.login == $o)
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
              .[]
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
              .[]
              | [ "\($rel)/\(.name)",
                  ((.description // "") | gsub("[\\t\\n\\r]"; " ")),
                  ((.topics // []) | join(",")) ]
              | @tsv
            ' 2>/dev/null
        ;;
    esac
  )
}
```

- [ ] **Step 2: Verify the new output shape**

On a machine with a populated GitHub token (e.g. WSL2 box):

```bash
source ~/.bash_aliases_clrepo 2>/dev/null || source shell/clrepo.sh
_clrepo_fetch_target github/freaxnx01/public github freaxnx01 public | head -3
```

Expected: TSV lines like:
```
github/freaxnx01/public/config<TAB>Shell config etc.<TAB>dotfiles,shell
github/freaxnx01/public/some-repo<TAB><TAB>
```

Three tab-separated columns per line. Empty description/topics are empty strings (not "null"). Run `| cat -A` to make tabs visible if needed.

- [ ] **Step 3: Commit**

```bash
git add shell/clrepo.sh
git commit -m "clrepo: widen _clrepo_fetch_target output to include description and topics"
```

---

## Task 2: Write `repo-meta.json` from `_clrepo_remote_list`

**Why:** The widened `_clrepo_fetch_target` now emits metadata; persist it to a JSON cache so the search helper can read it quickly without re-hitting APIs.

**Files:**
- Modify: `shell/clrepo.sh:92-114` (function `_clrepo_remote_list`)

**Design decision — cache shape:**
```json
{
  "github/freaxnx01/public/config": {
    "description": "Shell config, clrepo launcher, oh-my-posh, etc.",
    "topics": ["dotfiles", "shell"],
    "fetched_at": 1745000000
  }
}
```

Keyed by the same `rel` path clrepo uses everywhere else.

- [ ] **Step 1: Replace `_clrepo_remote_list` body**

Replace lines 92-114 of `shell/clrepo.sh` with:

```bash
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
      | while IFS=$'\t' read -r rpath desc topics_csv; do
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
```

- [ ] **Step 2: Verify the cache is written correctly**

```bash
rm -f ~/.cache/clrepo/remote.list ~/.cache/clrepo/repo-meta.json
clrepo --refresh </dev/null >/dev/null 2>&1 &
sleep 30 && kill %1 2>/dev/null
cat ~/.cache/clrepo/repo-meta.json | jq 'to_entries | .[0:3]'
```

Expected: a JSON object keyed by rel paths, each entry containing `description`, `topics` (array), `fetched_at` (unix ts).

- [ ] **Step 3: Verify the picker still streams paths**

```bash
clrepo -r
```

Expected: fzf picker opens, populated exactly like before (paths only, uncloned remotes prefixed with `↓`). No regression.

Exit fzf with Esc.

- [ ] **Step 4: Commit**

```bash
git add shell/clrepo.sh
git commit -m "clrepo: persist forge metadata to repo-meta.json alongside remote.list"
```

---

## Task 3: Add `_clrepo_meta_search` helper

**Why:** Pure function that reads `repo-meta.json` and returns matches, classified by hit type. Keeps matching logic out of the main `clrepo()` function so it's easy to reason about.

**Files:**
- Modify: `shell/clrepo.sh` — add new function between `_clrepo_remote_list` (ends ~line 130) and `_clrepo_clone_url` (line 116 today).

**Design decision — output format:**
TSV per line: `<hit_type>\t<rel_path>\t<snippet>`
- `hit_type`: `topic` or `desc`
- `rel_path`: the repo path
- `snippet`: for `topic` hits, the matched topic name; for `desc` hits, a ~50-char window around the match

Sorted with all `topic` rows first, then `desc` rows. Within each group, sorted by rel_path basename.

- [ ] **Step 1: Add the new function**

Insert the following after the closing `}` of `_clrepo_remote_list` (before `_clrepo_clone_url`):

```bash
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

    to_entries
    | map(. as $entry
          | ($entry.value.topics // [])
          | map(select(contains_ci($kw; .)))
          | map({ type: "topic", path: $entry.key, snippet: . })
         ) | add // []
    | . as $topics
    | (to_entries
       | map(select(
             ($topics | map(.path) | index(.key)) == null
             and contains_ci($kw; (.value.description // ""))
           ))
       | map({ type: "desc", path: .key,
               snippet: (snippet(.value.description; $kw)) })
      ) as $descs
    | ($topics | sort_by(.path | split("/") | last))
      + ($descs | sort_by(.path | split("/") | last))
    | .[]
    | [.type, .path, .snippet] | @tsv
  ' "$meta" 2>/dev/null
}
```

- [ ] **Step 2: Verify the search against the populated cache**

Prerequisites: Task 2 populated `repo-meta.json`. Add a topic to the `config` repo to give yourself a known target:

```bash
gh repo edit freaxnx01/config --add-topic claude-dev
clrepo --refresh </dev/null >/dev/null 2>&1 &
sleep 30 && kill %1 2>/dev/null
```

Then:

```bash
source shell/clrepo.sh
_clrepo_meta_search claude-dev
```

Expected output (one or more lines, first by `config`):
```
topic	github/freaxnx01/public/config	claude-dev
```

Also test a description miss → no output, and a keyword that hits both fields in the same repo → one `topic` line (no `desc` duplicate):

```bash
_clrepo_meta_search zzzznomatchzzzz   # should print nothing
_clrepo_meta_search dotfiles           # topic hits for whatever repos are tagged
```

- [ ] **Step 3: Commit**

```bash
git add shell/clrepo.sh
git commit -m "clrepo: add _clrepo_meta_search helper"
```

---

## Task 4: Wire metadata fallback into `clrepo()` positional branch

**Why:** The helper is ready. Now hook it in: after an exact-name miss, try `_clrepo_meta_search`, handle 0/1/2+ cases.

**Files:**
- Modify: `shell/clrepo.sh:794-800` (positional shortcut branch inside `clrepo()`)

Current code:

```bash
  # Positional shortcut: case-insensitive exact-basename lookup, local-only.
  if [ "$mode_delete" = 0 ] && [ -n "$1" ]; then
    local sel
    sel=$(printf '%s\n' "$all" | grep -Ei "(^|/)$1$" | head -1)
    [ -z "$sel" ] && { echo "clrepo: no such repo: $1"; return 1; }
    _clrepo_launch "$sel" "$worktree"
    return
  fi
```

**Design decision — cloning on 1-hit:**
If the single metadata hit is an uncloned remote (path not present in the local-scan `all`), clone it first via `_clrepo_clone_remote` exactly the way the picker path does.

- [ ] **Step 1: Replace the positional branch**

Replace the block above with:

```bash
  # Positional shortcut: case-insensitive exact-basename lookup, local-only.
  # If name misses, fall back to metadata (topics + description) search.
  if [ "$mode_delete" = 0 ] && [ -n "$1" ]; then
    local sel
    sel=$(printf '%s\n' "$all" | grep -Ei "(^|/)$1$" | head -1)
    if [ -n "$sel" ]; then
      _clrepo_launch "$sel" "$worktree"
      return
    fi

    # Name miss — try metadata search.
    local meta_hits count hit_path was_remote=0
    meta_hits=$(_clrepo_meta_search "$1")
    count=$(printf '%s' "$meta_hits" | grep -c '^' 2>/dev/null || echo 0)

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
      _clrepo_launch "$hit_path" "$worktree"
      return
    fi

    # 2+ hits — annotated fzf picker.
    local pick
    pick=$(printf '%s\n' "$meta_hits" \
      | awk -F'\t' '{ printf "%-50s  [%s: %s]\n", $2, $1, $3 }' \
      | fzf --height=40% --reverse --prompt="match '$1'> " --with-nth=1..) || return
    hit_path=$(printf '%s' "$pick" | awk '{print $1}')
    [ -z "$hit_path" ] && return
    printf '%s\n' "$all" | grep -qxF "$hit_path" || was_remote=1
    if [ "$was_remote" = 1 ]; then
      _clrepo_clone_remote "$hit_path" || return 1
    fi
    _clrepo_launch "$hit_path" "$worktree"
    return
  fi
```

- [ ] **Step 2: Verify — existing name match unaffected**

```bash
clrepo config
```

Expected: launches Claude in `github/freaxnx01/public/config` as it did before. Detach (`Ctrl-B D`) or `/exit`.

- [ ] **Step 3: Verify — keyword fallback works (single hit)**

With the `claude-dev` topic added to `config` in Task 3:

```bash
clrepo claude-dev
```

Expected: launches Claude in `config` (same outcome as `clrepo config`). No picker — single hit auto-launches. Detach/exit.

- [ ] **Step 4: Verify — keyword fallback works (multiple hits)**

Add the topic to a second repo to force a multi-hit scenario:

```bash
gh repo edit freaxnx01/claude-code-plugins --add-topic claude-dev
clrepo --refresh </dev/null >/dev/null 2>&1 &
sleep 30 && kill %1 2>/dev/null
clrepo claude-dev
```

Expected: fzf opens showing both repos with `[topic: claude-dev]` annotation. Select one with Enter; Claude launches. Detach/exit.

Cleanup if desired: `gh repo edit freaxnx01/claude-code-plugins --remove-topic claude-dev`.

- [ ] **Step 5: Verify — miss path unchanged**

```bash
clrepo zzzznomatchzzzz
```

Expected: `clrepo: no such repo: zzzznomatchzzzz` on stderr, exit code 1. Same as today.

- [ ] **Step 6: Commit**

```bash
git add shell/clrepo.sh
git commit -m "clrepo: fall back to metadata search when name match misses"
```

---

## Task 5: Invalidate `repo-meta.json` on `--refresh`

**Why:** The existing `--refresh` flag (and `Ctrl-R` in the picker, which invokes `clrepo --refresh`) invalidates `remote.list`. `repo-meta.json` needs the same treatment so the next populate overwrites it with fresh data.

**Files:**
- Modify: `shell/clrepo.sh` — `_clrepo_remote_list` force-refresh branch (already handles it correctly, since Task 2 unconditionally writes `tmp_meta` → `meta_cache` on every non-cached run). Verify no extra change is needed.

- [ ] **Step 1: Audit the refresh path**

Re-read `_clrepo_remote_list` after Task 2's edit. The logic is:

```
if not force AND cache exists AND cache age < TTL:
    cat cache; return
# otherwise: refetch, write both tmp_list and tmp_meta, mv into place
```

When `force=1`, the `if` short-circuits and the refetch runs, which overwrites `repo-meta.json`. No change needed.

- [ ] **Step 2: Verify refresh actually rewrites both files**

```bash
ls -la ~/.cache/clrepo/remote.list ~/.cache/clrepo/repo-meta.json
clrepo --refresh </dev/null >/dev/null 2>&1 &
sleep 30 && kill %1 2>/dev/null
ls -la ~/.cache/clrepo/remote.list ~/.cache/clrepo/repo-meta.json
```

Expected: mtimes on both files advance.

- [ ] **Step 3: No commit needed for this task** (it was a verification-only task).

---

## Task 6: Document the feature

**Why:** `CLREPO.md` is the user-facing cheat sheet. Update it so `clrepo <keyword>` behavior is discoverable.

**Files:**
- Modify: `shell/CLREPO.md`

- [ ] **Step 1: Read current content**

```bash
cat shell/CLREPO.md
```

Identify the "Basic usage" / "Surface" section that documents `clrepo <name>`.

- [ ] **Step 2: Add a paragraph near the basic-usage table**

Insert (adapt phrasing to match the existing doc style):

```markdown
### Keyword lookup

If `clrepo <name>` doesn't match a local repo, it falls back to searching
**topics and description** across cached forge metadata (populated by `-r`
or `--refresh`). Topic hits rank above description hits.

- 1 hit → auto-launches (clones first if the hit is a remote repo you don't have locally).
- 2+ hits → fzf picker annotated with what matched, e.g. `config  [topic: claude-dev]`.

Tip: tag repos you want keyword-reachable with a GitHub/GitLab/Forgejo topic:

    gh repo edit <owner>/<repo> --add-topic <keyword>
```

- [ ] **Step 3: Commit docs**

```bash
git add shell/CLREPO.md
git commit -m "docs: document clrepo keyword metadata fallback"
```

---

## Task 7: Cross-machine rollout

**Why:** clrepo is used from three machines (claude-dev LXC, WSL2 on Win11, company notebook). Verify the feature works on each one, since each has different forge credentials in direnv-loaded `.envrc` files.

**Files:** none — this is operational verification.

- [ ] **Step 1: Push the branch and merge**

```bash
git push
```

Review the diff on GitHub if desired, then fast-forward main if work was on a branch. (If you committed directly to main on the WSL2 box, the push already did this.)

- [ ] **Step 2: Pull on claude-dev LXC**

SSH in and pull:

```bash
ssh claude-dev
cd ~/projects/repos/github/freaxnx01/public/config
git pull
# Reload shell or source the updated file:
source shell/clrepo.sh
clrepo --refresh </dev/null >/dev/null 2>&1 &
sleep 30 && kill %1 2>/dev/null
clrepo claude-dev
```

Expected: launches Claude on `config`.

- [ ] **Step 3: Pull on company notebook**

Same procedure as Step 2 in whatever directory holds the config clone there.

- [ ] **Step 4: Confirm**

After each machine has been tested, the feature is live. No code change in this task.

---

## Self-Review

**Spec coverage:** All sections of the spec (`docs/superpowers/specs/2026-04-19-clrepo-keyword-metadata-search-design.md`) map to tasks:
- Match flow → Task 4
- Metadata source + cache → Tasks 1, 2
- Refresh triggers (TTL, clone-time opportunistic, Ctrl-R) → Tasks 2, 5. Opportunistic-on-clone is NOT implemented as a separate task — the next `--refresh` picks it up. This is a deliberate scope trim: `_clrepo_clone_remote` already invalidates `remote.list`, so the next picker invocation with `-r` will refetch everything. Adding a targeted single-repo metadata refresh is YAGNI.
- Matching rules → Task 3 (`_clrepo_meta_search`)
- Picker annotation → Task 4 (awk formatter)
- Changes to `clrepo.sh` enumeration → covered across Tasks 1-5.
- Out-of-scope items (local-only repos, no background warming) stay out of scope.
- Success criteria (topic on `config`, `clrepo claude-dev` works, existing flows unchanged, no new deps) → Tasks 3, 4, 7.

**Placeholder scan:** No "TBD" / "implement later" / "handle edge cases" in any task. Every code step contains the code to paste.

**Type consistency:** Function names consistent across tasks: `_clrepo_fetch_target`, `_clrepo_remote_list`, `_clrepo_meta_search`, `_clrepo_clone_remote`, `_clrepo_launch`. Cache file paths consistent: `~/.cache/clrepo/remote.list` (existing), `~/.cache/clrepo/repo-meta.json` (new). TSV output shape consistent between fetch-target (3 cols: path, desc, topics) and meta-search (3 cols: type, path, snippet) — documented at each function's comment.

**One intentional simplification:** The spec's matching rules say "A repo with both a topic hit and a description hit counts as a topic hit." The jq in Task 3 implements this by filtering description hits to exclude paths already in the topic-hit set.
