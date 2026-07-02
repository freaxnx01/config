---
description: End the session — summarize loose ends and write them to TODO.md
---

Review what has happened in this session and write any unfinished work to `TODO.md`
in the repo root.

## Steps

1. **Identify loose ends** — same scan as `/loose-ends`: edits not committed, tests
   not run or failing, commands queued, follow-ups requested, open TODOs, agent PRs
   still in flight.

2. **Write `TODO.md`** — create or overwrite `TODO.md` at the repo root. Group items
   under meaningful headings (e.g. by PR, feature, or topic). Each item is a checkbox:
   `- [ ] <what needs doing>`. Include enough context per item that it's actionable
   cold (PR number, file path, what was waiting on what).

3. **Commit and push `TODO.md`** — if the file was written (i.e. there are loose ends),
   stage and commit it with message `chore: update TODO.md` and push to the current
   branch's remote. Skip if nothing was written.

4. **Print a short summary** — one line per loose end, then confirm the path written
   and pushed. If there's nothing outstanding, say so and skip writing the file.

Keep it terse. No preamble.

> **Related:** `/wrap-up` captures *all* session loose ends. To save and resume a
> *single* in-flight task across a `/clear`, use `/handoff` → `/pickup` instead.
