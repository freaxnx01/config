---
description: Git status — uncommitted/untracked, branches, worktrees, cleanup check
---

Read-only inspection of the current repo — don't change the working tree or any
branches (a `git fetch` to refresh remote-tracking refs is fine). Report concisely:

1. **Working tree** — uncommitted (staged + unstaged) and untracked files.
   `git status --short --branch` is enough; summarize, don't dump huge lists.
2. **Behind/ahead of remote** — first `git fetch --quiet` (network read; updates
   only remote-tracking refs, no working-tree change), then report whether the
   current branch is **behind** its upstream (needs a pull), ahead (needs a push),
   or up to date — e.g. `git rev-list --left-right --count @{u}...HEAD`. If the
   branch has no upstream, say so.
3. **Branches** — local branches with upstream + ahead/behind (`git branch -vv`),
   and which are already merged into the default branch
   (`git branch --merged <default>`).
4. **Worktrees** — `git worktree list`; mark which one is the current directory and
   which is the primary checkout. Flag any `prunable` entries
   (`git worktree list --porcelain` shows them).
5. **Can the current worktree be cleaned up?** Give a clear yes/no with the reason.
   Safe to clean up when ALL hold:
   - the current dir is a **linked worktree**, not the primary checkout;
   - the working tree is **clean** (no uncommitted or untracked files);
   - its branch is **merged into the default branch** *or* fully pushed to its
     upstream (nothing would be lost).
   If safe, point me at `/wt:finish` (or `git worktree remove`). If not, list
   exactly what's blocking. If we're not in a worktree at all, say so.

Determine the default branch from `git symbolic-ref --quiet refs/remotes/origin/HEAD`
(fall back to `main`/`master`).

## Output format

Start with **one prominent recap line** — a quick verdict with a leading `✓` (all
good) or `⚠` (attention), e.g.
`✓ clean · up to date with origin/main · primary checkout — nothing to clean up`
or `⚠ 3 uncommitted · 2 behind origin/main · worktree ready to clean up`.

Then a compact ASCII table covering the five checks, e.g.:

```
┌──────────────┬───────────────────────────────────────────┐
│ Check        │ Status                                     │
├──────────────┼───────────────────────────────────────────┤
│ Working tree │ clean (0 staged, 0 unstaged, 0 untracked)  │
│ Remote       │ up to date (0 behind, 0 ahead)             │
│ Branch       │ main → origin/main, merged                 │
│ Worktree     │ primary checkout                           │
│ Cleanup      │ N/A — not a linked worktree                │
└──────────────┴───────────────────────────────────────────┘
```

After the table, only if relevant: list multiple worktrees, and a short bullet list
of anything **blocking** cleanup. Keep it terse — no other preamble.
