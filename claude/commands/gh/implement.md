---
description: Validate issue readiness, then label it ai-implement so the agent-pipeline picks it up and opens a draft PR
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
4. **Issue is ready for an agent** — read the full issue body and comments with
   `gh issue view <N> --comments`, then judge whether an AI agent has enough to
   implement it without guessing. A ready issue has **all three**:
   - **Acceptance criteria** — concrete, testable conditions ("given X, when Y, then Z";
     or a checklist of behaviours). Vague goals ("make it better") don't count.
   - **Scope / spec** — what to build: endpoints, data model, UI behaviour, or a
     concise implementation plan. The agent must be able to start without asking
     clarifying questions.
   - **No blocking unknowns** — no open design questions, unresolved dependencies, or
     "TBD" placeholders that the agent cannot resolve from the codebase alone.

   If any of the three is missing, **stop** — do not label. Tell the user specifically
   what's missing and suggest they add it to the issue body before re-running.
   If it carries `needs-enrichment` or `❓ to-be-defined`, treat that as a hard stop
   (don't just warn — the label signals the issue is not ready).

## Post TDD contract

Post a TDD requirement comment on the issue so the pipeline agent reads it as part
of the issue context:

```bash
gh issue comment <N> --body "## TDD Required — Non-Negotiable

Implement using Test-Driven Development:
- **RED:** Write a failing test first. Run it. Confirm it fails for the right reason.
- **GREEN:** Write the minimal code to make it pass. No more.
- **REFACTOR:** Clean up while keeping tests green.

No production code without a failing test first.

Your PR description must include TDD evidence:
- RED: command run + relevant failing output
- GREEN: command run + passing output"
```

Replace `<N>` with the actual issue number.

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
