---
description: List my custom slash commands (user + project), grouped
---

List **my custom** slash commands — not the built-ins or plugin-provided ones.

Scan both command directories:
- user/global: `~/.claude/commands/`
- this project: `./.claude/commands/` (only if it exists)

For every `*.md` file (recurse into subdirs, skip any `README.md`), derive the
command name from its path — `foo.md` → `/foo`, and `ns/foo.md` → `/ns:foo` — and
read its `description:` front-matter. Prefer one shell pass over reading files
individually, e.g.:

```bash
for d in ~/.claude/commands ./.claude/commands; do
  [ -d "$d" ] || continue
  find "$d" -name '*.md' ! -name 'README.md' | while read -r f; do
    name=$(printf '%s' "${f#"$d"/}" | sed 's/\.md$//; s#/#:#g')
    desc=$(sed -n 's/^description: *//p' "$f" | head -1)
    printf '/%s — %s\n' "$name" "$desc"
  done
done
```

Present grouped by **source** (User vs Project), and within each keep namespaced
families together (all `/gh:*`, etc.). Show `/<name> — <description>`, sorted
sensibly, and give the total count. If a directory is missing or empty, say so in
one line.

## Example workflows (command "linking")

After the listing, add an **Example workflows** section showing how the commands
chain. Render each as an arrow chain (`→`) with a one-line purpose. Only include a
chain if all its commands actually exist in the scan above — drop any step whose
command is missing, and skip a whole chain if its backbone is gone. Adapt the
labels (gh vs fj) to whichever families are present.

Use these as the baseline set:

- **Issue pipeline (GitHub):** `/gh:new` → `/gh:triage` → `/gh:route` → `/gh:enrich` → `/gh:work` → `/gh:review` → `/gh:prs` → `/gh:done`
  _Capture an idea, prioritize, decide how to build it, spec it, implement, review, merge, archive._
- **Delegate to an AI agent:** `/gh:route` → `/gh:enrich-phased` → `/gh:assign` (or `/gh:implement`) → `/gh:review`
  _Hand a well-specced issue to @copilot/@claude or the agent-pipeline instead of building it locally._
- **Forgejo pipeline:** `/fj:new` → `/fj:triage` → `/fj:route` → `/fj:enrich` → `/fj:work` → `/fj:prs` → `/fj:done`
  _Same flow as GitHub, on the self-hosted Forgejo instance._
- **Session continuity (clear & resume):** `/loose-ends` → `/clear-check` → `/handoff` → `/clear` → `/pickup`
  _Wrap up mid-task, confirm it's safe to clear, save state, then resume in a fresh context._
- **Session wrap / next day:** `/wrap-up` → (`/clear` or new session) → `/todo`
  _End a session into TODO.md, then re-orient the next session around what's pending._
- **Worktree feature work:** `/wt:status` → `/gh:work` (or `/fj:work`) → `/wt:finish`
  _Check the tree is clean, do isolated feature work, then commit/merge/clean up._

Keep this section concise — it's a cheat-sheet, not documentation. Note that `/clear`
is a built-in (it appears in chains for context but isn't one of my custom commands).
