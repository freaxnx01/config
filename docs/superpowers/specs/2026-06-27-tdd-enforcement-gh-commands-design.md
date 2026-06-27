# TDD Enforcement in gh:work, gh:implement, gh:assign

**Date:** 2026-06-27  
**Status:** Approved

## Problem

TDD was not enforced on any of the three primary implementation paths:

- `/gh:work` — TDD only applied "if the task says to" (conditional in the implementer template)
- `/gh:implement` — pipeline prompt says "read CLAUDE.md" but never calls out TDD explicitly
- `/gh:assign` — delegates entirely to Copilot/Anthropic agent with no TDD instruction

## Goal

Every implementation triggered through these three commands uses Test-Driven Development — no production code before a failing test, on all paths.

## Scope

Changes are config-repo-only (`claude/commands/gh/`). No changes to `agent-pipeline` or any other repo.

## Design

### `/gh:work`

Add one sentence to the plan-writing step (step 3):

> "TDD is a non-negotiable global constraint — include it verbatim in the plan's Global Constraints section."

**Why this works:** `superpowers:writing-plans` produces a plan with a Global Constraints section. `superpowers:subagent-driven-development` extracts that section into every implementer's task brief via `scripts/task-brief`. The implementer template already has a conditional TDD evidence block in its report format; with TDD in Global Constraints it becomes unconditional.

### `/gh:implement` and `/gh:assign`

Add a **Post TDD contract** step in each command, positioned after precondition checks and before the label/assign action.

The step posts this comment on the issue via `gh issue comment`:

```markdown
## TDD Required — Non-Negotiable

Implement using Test-Driven Development:
- **RED:** Write a failing test first. Run it. Confirm it fails for the right reason.
- **GREEN:** Write the minimal code to make it pass. No more.
- **REFACTOR:** Clean up while keeping tests green.

No production code without a failing test first.

Your PR description must include TDD evidence:
- RED: command run + relevant failing output
- GREEN: command run + passing output
```

**Why a comment:** Both the agent-pipeline (`gh issue view --comments` in `claude-implement.yml`) and GitHub coding agents (Copilot SWE agent, Anthropic code agent) read the full issue thread. The comment appears in the permanent issue history and is visible to human reviewers when checking PR compliance.

**Placement:** After the readiness/precondition check — we don't comment on issues that fail preconditions and would be stopped anyway.

## Files Changed

| File | Change |
|---|---|
| `claude/commands/gh/work.md` | Add TDD global constraint instruction to step 3 |
| `claude/commands/gh/implement.md` | Add Post TDD contract step before label |
| `claude/commands/gh/assign.md` | Add Post TDD contract step before assign |

## Out of Scope

- `agent-pipeline/claude-implement.yml` — not touched (config-repo-only decision)
- `ai-instructions/CLAUDE.md` template — already has TDD testing rules; not changed
- `/gh:enrich`, `/gh:new`, `/gh:triage` — these don't trigger implementation
