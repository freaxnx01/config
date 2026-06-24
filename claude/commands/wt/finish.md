---
description: Commit, merge, and clean up the current worktree branch
---

Finish the current worktree/branch: commit outstanding work, integrate it, and
clean up. Drive this with the **superpowers:finishing-a-development-branch** skill
(it presents merge / PR / cleanup options).

Default intent here is **commit + merge into the default branch + remove the
worktree**, but:

- First show me uncommitted changes and exactly what will be merged; confirm
  before any destructive step.
- Verify the branch is green (tests/build) before merging — if anything fails,
  stop and report.
- Commit anything outstanding with a clear message (reference the issue number if
  this branch came from `/gh:work`).
- Merge into the default branch, then remove the worktree and delete the merged
  branch (per **superpowers:using-git-worktrees** cleanup).

Never force-push or discard uncommitted work without asking.
