# clrepo local-first update check — design

**Date:** 2026-05-03
**Component:** `shell/clrepo.sh` — function `_clrepo_check_latest`
**Issue:** [#6](https://github.com/freaxnx01/config/issues/6)

## Problem

`_clrepo_check_latest` (currently at `shell/clrepo.sh:1298`) compares the in-memory `$_CLREPO_VERSION` of the running shell against the latest version published to GitHub by curl-ing the raw URL of `clrepo.sh` on `main`. The result is cached at `$_CLREPO_CACHE/latest-version` with a 24h TTL and refreshed in a backgrounded subshell.

This ignores the on-disk copy that the running shell was sourced from. In the developer's normal workflow:

1. The script is sourced from the local config repo at `~/projects/repos/github/freaxnx01/public/config/shell/clrepo.sh`.
2. `_clrepo_autosync` already keeps that working tree in sync with origin (background `git pull --ff-only`).
3. While editing `clrepo.sh` the developer bumps `_CLREPO_VERSION` and saves — the on-disk version is now ahead of what the running shell has loaded.
4. The remote check is irrelevant: the autosync has already fetched origin into the working tree, and the developer's own edit is ahead of both. The right next step is to re-source the local file (`clrepo update`), not to compare against GitHub.

Hitting the network here is unnecessary on the happy path and noisy when the network is flaky.

## Goal

Have `_clrepo_check_latest` consult the on-disk copy of `clrepo.sh` first. Only fall back to the remote curl when the on-disk copy can't be located or read (e.g. the script was copied to a non-repo path on a fresh machine).

## Non-goals

- Not changing `_clrepo_update`. It already operates on `BASH_SOURCE[0]` and is local-correct.
- Not changing `_clrepo_autosync`. Pulling origin into the working tree remains its job.
- Not adding a `git fetch` from `_clrepo_check_latest`. Autosync owns that.
- Not adding new commands or flags.

## Design

### New control flow for `_clrepo_check_latest`

```
1. Resolve on-disk path:
     script="${BASH_SOURCE[0]}"
     command -v readlink >/dev/null && script=$(readlink -f "$script" 2>/dev/null || echo "$script")

2. If $script is readable:
     latest=$(grep -m1 '^_CLREPO_VERSION=' "$script" \
              | sed -E 's/^_CLREPO_VERSION="?([^"]+)"?.*/\1/')
     if [ -n "$latest" ]:
       if _clrepo_version_gt "$latest" "$_CLREPO_VERSION":
         print hint, return.
       else:
         return silently.   # in-memory is up-to-date with on-disk; no remote check needed.

3. Fallback (on-disk path not resolvable, file unreadable, or no _CLREPO_VERSION line):
     existing TTL-gated remote curl + cache logic, unchanged.
```

The fallback is a verbatim copy of today's body (curl into `$_CLREPO_CACHE/latest-version` under `flock`, then read-and-compare). Only the prelude is new.

### What goes away on the happy path

- The background curl subshell.
- The `$_CLREPO_CACHE/latest-version` cache write/read.
- The `$_CLREPO_CACHE/latest-warm.lock` flock.

These remain in the function (under the fallback branch) but are unreachable when `BASH_SOURCE[0]` resolves to a readable file with a parseable version line — i.e. the developer's normal setup.

### Edge cases

| Case | Behavior |
|---|---|
| On-disk file present, version > in-memory | Print existing hint, return. No network. |
| On-disk file present, version == in-memory | Return silently. No hint, no network. |
| On-disk file present, version < in-memory | Return silently. (User has somehow downgraded the file; in-memory is newer than what re-sourcing would load. Remote curl can't help here either.) |
| On-disk file present but no `_CLREPO_VERSION` line (corrupted, partial copy) | Fall back to remote curl. |
| `BASH_SOURCE[0]` resolves to an unreadable path (permissions, deleted file) | Fall back to remote curl. |
| `readlink` not installed | Use `BASH_SOURCE[0]` as-is — same defensive pattern already used in `_clrepo_update` (`shell/clrepo.sh:1326`). |

### Why no `git` operation here

Two reasons:
- `_clrepo_autosync` already runs `git fetch` + `ff-only merge` in the background on every `clrepo` invocation, so origin's version is normally already on disk by the time `_clrepo_check_latest` runs.
- Adding a synchronous `git` call inside the prompt-time hint path would slow it down. The whole point of the existing function is that the curl was backgrounded; reading the on-disk file is even cheaper.

## Implementation notes

- Reuse the existing `_clrepo_version_gt` helper for the comparison.
- Reuse the existing grep/sed pattern verbatim — same source format, same parser.
- Keep the function name and signature unchanged. Single call site (`shell/clrepo.sh:1448`) needs no edits.

## Testing (manual)

Three scenarios on `claude-dev`:

1. **Up-to-date** — fresh shell, on-disk version == sourced version. Run any `clrepo` command. Expect: no hint, no curl. Verify by `strace -fe trace=network` or by deleting `$_CLREPO_CACHE/latest-version` first and confirming it does not get re-created.
2. **Local edit ahead of in-memory** — bump `_CLREPO_VERSION` in the on-disk file (without re-sourcing). Run `clrepo --status` (or any command that triggers the hint). Expect: `clrepo: new version X available — run \`clrepo update\``. Confirm `clrepo update` then re-sources and clears the hint.
3. **Fallback** — `cp clrepo.sh /tmp/clrepo.sh && source /tmp/clrepo.sh` after also `chmod 000 /tmp/clrepo.sh` (or simpler: `source` it then `rm` the file). Trigger the hint path. Expect: it falls through to the existing remote curl behavior. (This scenario is unusual but covers users who installed clrepo into a non-repo path.)

## Versioning

`_CLREPO_VERSION` patch bump per `CLAUDE.md`: `1.13.0` → `1.13.1`. Internal behavior change, no new commands.

## Out of scope / follow-ups

- Issues #5, #7, #8 from the same enhancement batch are tracked separately and will be addressed in subsequent specs.
