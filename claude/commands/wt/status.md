---
description: Git status — uncommitted/untracked, branches, worktrees, cleanup check
---

Read-only inspection of the current repo. Make **no** changes. Report concisely:

1. **Working tree** — uncommitted (staged + unstaged) and untracked files, plus
   ahead/behind vs upstream. `git status --short --branch` is enough; summarize,
   don't dump huge lists.
2. **Branches** — local branches with upstream + ahead/behind (`git branch -vv`),
   and which are already merged into the default branch
   (`git branch --merged <default>`).
3. **Worktrees** — `git worktree list`; mark which one is the current directory and
   which is the primary checkout. Flag any `prunable` entries
   (`git worktree list --porcelain` shows them).
4. **Can the current worktree be cleaned up?** Give a clear yes/no with the reason.
   Safe to clean up when ALL hold:
   - the current dir is a **linked worktree**, not the primary checkout;
   - the working tree is **clean** (no uncommitted or untracked files);
   - its branch is **merged into the default branch** *or* fully pushed to its
     upstream (nothing would be lost).
   If safe, point me at `/wt:finish` (or `git worktree remove`). If not, list
   exactly what's blocking. If we're not in a worktree at all, say so.

Determine the default branch from `git symbolic-ref --quiet refs/remotes/origin/HEAD`
(fall back to `main`/`master`).
