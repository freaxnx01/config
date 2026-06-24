---
description: Recently implemented (closed) issues
---

List recently implemented issues — closed issues, most recently closed first:

`gh issue list --state closed --limit 30 --json number,title,closedAt,labels,stateReason --jq 'sort_by(.closedAt) | reverse'`

Prefer issues closed as **completed** (`stateReason` = `COMPLETED`); list any that
were closed **not planned** separately at the end. Compact table: number, title,
when closed (relative), labels. Concise.
