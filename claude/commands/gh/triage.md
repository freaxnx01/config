---
description: Open issues ordered bugs/fixes first, then quick wins
---

Fetch open issues with body + labels
(`gh issue list --state open --limit 100 --json number,title,labels,body,createdAt`),
then present them ordered for triage:

1. **Bugs / fixes first** — issues whose labels or title/body signal a defect
   (labels like `bug`, `type:bug`, `defect`, `regression`, `fix`; or clear
   bug wording).
2. **Then quick wins** — remaining low-complexity / small-scope issues
   (short, well-defined; labels like `good-first-issue`, `chore`, `docs`,
   `small`). Easiest first, by your judgment from title/body/labels.
3. **Everything else** after that.

For each: number, title, key labels, and a 3–6 word reason it's in that bucket.
Be concise — this is a reading aid, don't start any work.
