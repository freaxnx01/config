---
description: Work on issue #N — plan then subagent-driven implementation
argument-hint: <issue number>
---

Implement GitHub issue #$ARGUMENTS end to end (strip any leading `#` from the
number):

1. `gh issue view $ARGUMENTS --comments` — read the issue and its discussion.
2. If scope or requirements are unclear or open-ended, use the
   **superpowers:brainstorming** skill to settle them before any code.
3. Use **superpowers:writing-plans** to produce an implementation plan (markdown).
   TDD is a non-negotiable global constraint — include it verbatim in the plan's
   Global Constraints section: "Use Test-Driven Development for every task: write
   a failing test first, watch it fail, implement minimally to pass, verify green."
4. Create an isolated workspace with **superpowers:using-git-worktrees**, on a
   branch named for the issue (e.g. `issue-$ARGUMENTS-<slug>`).
5. Execute the plan with **superpowers:subagent-driven-development**.
6. When implementation is complete **and verified**, stop and tell me it's ready
   for `/wt:finish` — do not merge yet.

Reference issue #$ARGUMENTS in commits. If the issue doesn't exist, say so and stop.
