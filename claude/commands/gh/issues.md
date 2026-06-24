---
description: List open issues, newest first
---

List open issues in the current repo, **newest first**:

`gh issue list --state open --limit 50 --json number,title,labels,createdAt,author --jq 'sort_by(.createdAt) | reverse'`

Show a compact table — number, title, labels, age (relative), author. No preamble.
If there are none, just say so.
