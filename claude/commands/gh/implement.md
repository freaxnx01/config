---
description: Label issue #N with ai-implement to kick off the agent-pipeline
argument-hint: <issue number>
---

Hand issue #$ARGUMENTS to the **agent-pipeline** by applying the `ai-implement` label.
Strip any leading `#` from the argument.

The pipeline trigger: `issues: labeled` → `claude.yml` in the current repo fires →
Claude Code implements the issue on a new branch and opens a draft PR.

## Preconditions — check before labeling

1. **Issue is open and not parked** — `gh issue view <N> --json state,labels`; stop if
   closed or carrying `🧊 parked`.
2. **Not already queued** — if `ai-implement` is already on the issue, say so and stop
   (avoid double-triggering).
3. **Pipeline is wired up** — `.github/workflows/claude.yml` must exist in the repo;
   if it doesn't, tell the user to run `/sync-ai-instructions` or wire up the pipeline
   first, then stop.
4. **Issue is actionable** — it should have clear scope/AC. If it carries
   `needs-enrichment` or `❓ to-be-defined`, warn the agent may produce a weak PR and
   ask the user to confirm before proceeding.

## Apply the label

Ensure the `ai-implement` label exists in the repo (create it if absent — color `#0075ca`,
description "Trigger: agent-pipeline Claude implementation"):

```bash
gh label create ai-implement --color "0075ca" --description "Trigger: agent-pipeline Claude implementation" --force
```

Then add it to the issue:

```bash
gh issue edit <N> --add-label ai-implement
```

## Report

Print:
- Issue number, title, and URL
- "agent-pipeline triggered — Claude will open a draft PR shortly"
- Remind the user to watch for a new PR and review it with `/gh:review` when it appears
