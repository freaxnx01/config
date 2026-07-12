---
description: Create a GitHub issue from notes, labeled needs-enrichment
argument-hint: <notes describing the issue>
---

Create a GitHub issue in the current repo with `gh issue create`.

- **Title**: a concise summary derived from my notes.
- **Body**: my notes, lightly cleaned up — keep my meaning, don't invent scope or
  pad. Add a short context line only if it's obvious from the repo.
- **Label**: `needs-enrichment` (always). If that label doesn't exist yet, create
  it first (`gh label create needs-enrichment` with a sensible color), then retry.
- Don't assign, milestone, or add other labels unless I said so.

After creating, print the issue number, title, and URL. If there's no `gh`/repo
context, say so and stop.

My notes:
$ARGUMENTS
