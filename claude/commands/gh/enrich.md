---
description: Enrich an issue with a spec and implementation plan, then update the issue body so the agent-pipeline can implement it
argument-hint: <issue number>
---

Enrich GitHub issue #$ARGUMENTS (strip any leading `#`) so it is ready for the
agent-pipeline. The pipeline reads only the issue **body** — everything the agent
needs must end up there.

## Step 1 — Read the issue

```bash
gh issue view $ARGUMENTS --comments
```

If the issue is closed, already has `ai-implement` label, or is `🧊 parked`, stop and say so.

## Step 2 — Assess readiness

Judge whether the issue already has all three:

- **Acceptance criteria** — concrete, testable conditions
- **Scope / spec** — what to build, enough to start without guessing
- **No blocking unknowns** — no open design questions or TBDs the agent can't resolve from the codebase

If the issue is already complete, tell the user and suggest running `/gh:implement $ARGUMENTS` directly. Stop here.

## Step 3 — Brainstorm spec

Invoke **superpowers:brainstorming** with the issue as context. The goal is a
validated spec saved to `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`
and committed. Follow the brainstorming skill end-to-end (clarifying questions,
approaches, design sections, spec self-review, user approval gate).

## Step 4 — Write implementation plan

After brainstorming exits, invoke **superpowers:writing-plans** to produce the
full task-by-task plan at `docs/superpowers/plans/YYYY-MM-DD-<topic>.md` and
commit it.

## Step 5 — Push to remote

Ensure both the spec and plan files are committed and pushed before touching the
issue body — the body will reference these files by path and the agent must be
able to check them out:

```bash
git push
```

Verify the push succeeded before proceeding.

## Step 6 — Update the issue body

Replace the issue body with:

1. The original description (keep it — context for humans)
2. An `## Acceptance Criteria` section with the approved AC as a `- [ ]` checklist
3. A `## Spec & Implementation Plan` section with:
   - Relative path to spec file (linked as markdown)
   - Relative path to plan file (linked as markdown)
   - A one-line instruction: _"Read the plan before writing any code — it contains the full task breakdown, file structure, TDD steps, and exact code to produce."_

```bash
gh issue edit $ARGUMENTS --body "..."
```

## Step 7 — Confirm

Print:
- Issue URL
- Paths to spec and plan files
- "Issue is ready — run `/gh:implement $ARGUMENTS` to trigger the agent-pipeline."

---

If you run into blockers (brainstorming skill not available, push fails, issue edit
rejected), find a solution and update this skill for the future.
