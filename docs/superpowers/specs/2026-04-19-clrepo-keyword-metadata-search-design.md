# clrepo keyword metadata search — design

**Date:** 2026-04-19
**Component:** `shell/clrepo.sh`

## Problem

`clrepo <name>` today only matches a repo by its basename. You must remember the exact repo name to jump to it. Example: the launcher script lives in `config`, but the mental handle for it is "claude-dev". Today `clrepo claude-dev` fails.

## Goal

Let a keyword find a repo by searching its platform metadata (topics + description) as a fallback when the name lookup misses. Zero per-repo bookkeeping: reuse fields the user already maintains on the forge.

## Non-goals

- No alias file, no per-repo keyword file, no sidecar config.
- No change to name-match behavior. Existing invocations keep working unchanged.
- No indexing of local-only repos outside `$_CLREPO_BASE` (e.g. `~/projects/local-repos/`). If a repo has no remote, it has no metadata to search.

## Match flow

Fallback chain on `clrepo <keyword>`. First non-empty wins.

1. **Exact local basename match** (current behavior, unchanged).
2. **Fuzzy local basename match** (current behavior, unchanged).
3. **NEW: metadata match** — search cached topics + descriptions across all known repos (both cloned clones and uncloned remotes discovered via the same forge APIs `-r` already uses).

Result handling at step 3:

- 1 hit → auto-launch (clone first if the hit is an uncloned remote, matching the `-r` flow).
- 2+ hits → fzf picker, annotated with the matched field:
  - `config  [topic: claude-dev]`
  - `config  [desc: …launcher for claude-dev LXC…]` (description snippet, centered on match, ~50 chars)

Topic hits rank above description hits. In the picker, topic hits appear first; within each group, sort by basename.

The `-r` flag is **not** required for step 3. The cache is local after its first populate, so metadata search is always cheap. `-r` keeps its current meaning — "include uncloned remotes in the picker listing."

## Metadata source and cache

**Source** — the forge APIs clrepo already calls in `_clrepo_fetch_target`:

- GitHub: `GET /user/repos` — already returns `description` and `topics` in the list response. No extra call needed.
- GitLab: `GET /projects?owned=true` — already returns `description` and `topics`.
- Forgejo: `GET /user/repos` — already returns `description` and `topics`.

All three platforms expose topics + description in the bulk listing the existing `_clrepo_fetch_target` function hits. We just need to capture those fields instead of discarding them.

**Cache file** — `~/.cache/clrepo/repo-meta.json`:

```json
{
  "github/freaxnx01/public/config": {
    "description": "Shell config, clrepo launcher, oh-my-posh, etc.",
    "topics": ["claude-dev", "dotfiles", "shell"],
    "fetched_at": 1745000000
  },
  ...
}
```

Keyed by the same `rel` path the rest of clrepo uses (`<forge>/<owner>[/<visibility>]/<name>`).

**Refresh triggers**:

- 7-day TTL. On any `clrepo` invocation that reaches step 3, entries older than 7d are refetched for their forge target before matching.
- Opportunistic: when a new remote is cloned (via picker or create-new), the cache entry for that repo is updated from the listing that discovered it.
- `Ctrl-R` in the picker (existing) now also refreshes `repo-meta.json`, not just the name listing.

**Failure mode**: if the forge API call fails for a target (no token, network error), keep stale cache entries and continue. No hard error; the keyword search just sees older metadata for that forge.

## Matching rules

- Case-insensitive substring match on the keyword against:
  - Each topic string (exact token match and substring match both count as "topic hit").
  - Description (substring match counts as "description hit").
- A repo with both a topic hit and a description hit counts as a topic hit.
- Tokenization: no fancy tokenizer. Substring over raw topic/description strings.

## Picker annotation

When step 3 produces results, each row in the fzf list gets a suffix:

```
config                                    [topic: claude-dev]
obsidian-homelab                          [desc: …notes about claude-dev LXC provisioning…]
```

Suffix is right-aligned or space-padded for readability; exact formatting follows the same style as the existing `↓ <name>` remote-marker convention. Only shown for step 3 results — step 1/2 results (name matches) look identical to today.

## Changes to `clrepo.sh`

Rough shape (details TBD during implementation):

1. Extend `_clrepo_fetch_target` to emit topics + description alongside each repo path. Either widen the stream format (TSV: `<rel>\t<description>\t<topics-csv>`) or write metadata to `repo-meta.json` in the same pass that writes `remote.list`.
2. Add `_clrepo_meta_search <keyword>` that reads `repo-meta.json` and emits matching `rel` paths with a classification prefix (`topic` / `desc`) and matched-field snippet.
3. In `clrepo()` positional handling, after the existing `grep -Ei "(^|/)$1$"` miss, call `_clrepo_meta_search`:
   - 0 hits → preserve current `clrepo: no such repo` error.
   - 1 hit → launch (clone first if remote).
   - 2+ hits → open fzf with the annotated list, then launch the selection.
4. Update `Ctrl-R` path to also refetch `repo-meta.json`.
5. Update completion function `_clrepo` to include topics as completion candidates (nice-to-have; can be deferred).

## Out of scope

- Handling of `~/projects/local-repos/` (repos without a remote). Separate concern, separate decision (either migrate those to a forge or extend `_CLREPO_BASE`).
- Ranking by match quality beyond topic-vs-description split. No BM25, no weighting by topic position, etc.
- Background cache warming. Refresh happens lazily on fallback use, not on a timer.

## Success criteria

After implementation and pushing the change through the config repo to all three machines (claude-dev LXC, WSL2 on Win11, company notebook):

1. `gh repo edit freaxnx01/config --add-topic claude-dev` (run once).
2. `clrepo claude-dev` lands in `config` and launches Claude, on all three machines.
3. `clrepo <known-name>` continues to work identically to today.
4. No new tokens, no new config files, no new dependencies beyond `jq` (already required).
