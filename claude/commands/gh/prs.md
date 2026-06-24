---
description: List pull requests awaiting review
---

Show open pull requests that need review in the current repo.

- **My review requested** (priority):
  `gh pr list --state open --search "review-requested:@me" --json number,title,author,createdAt,reviewDecision`
- **Also awaiting review** — other open PRs not authored by me with
  `reviewDecision` of `REVIEW_REQUIRED` or empty, so nothing slips through.

Compact table: number, title, author, age, review state. Exclude drafts unless
that's all there is. If none, say so.
