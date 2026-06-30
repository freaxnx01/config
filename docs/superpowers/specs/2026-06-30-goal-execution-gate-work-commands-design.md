# `/goal` as the execution-time verification gate in gh:work and fj:work

**Date:** 2026-06-30
**Status:** Approved (design) — implementation deferred

## Problem

`/gh:work` and `/fj:work` end with step 6: *"When implementation is complete **and
verified**, stop and tell me it's ready for `/wt:finish`."* Today "verified" is a
**manual judgment** by the orchestrating model after `superpowers:subagent-driven-development`
(SDD) reports the plan done. Nothing independently confirms the issue's acceptance
criteria (AC) actually hold before the run stops, so the agent can declare done while
an AC is unmet, leaving the user to re-prompt ("you missed X, fix it").

Claude Code's [`/goal`](https://code.claude.com/docs/en/goal) (v2.1.139+) keeps Claude
working across turns until a completion condition holds, with a separate small/fast
model (Haiku) evaluating the condition after **every** turn. It is a productized,
independently-verified convergence loop — exactly the "teeth" the word *verified* in
step 6 currently lacks.

## Goal

Turn the manual "complete **and verified**" judgment at the end of `/gh:work` and
`/fj:work` into an automated, independently-checked convergence loop that runs until
the issue's acceptance criteria demonstrably hold (or a turn bound is reached), then
stops for `/wt:finish`.

## Key facts about `/goal` that shape this design

- **Headless/interactive both work.** Used here interactively/locally inside the
  command flow; `claude -p "/goal …"` would also work but is out of scope.
- **The evaluator is tool-blind.** It judges only what Claude has surfaced in the
  **main** transcript; it does not run commands or read files. This is the central
  design constraint (see Risks).
- **It is a session-scoped prompt-based Stop hook.** Requires a trusted workspace and
  hooks enabled (not `disableAllHooks` / `allowManagedHooksOnly`). All trivially true
  for local runs.
- **Bound it in the condition.** `/goal` runs until the condition is met or `/goal
  clear`; a turn/time clause in the condition (e.g. `or stop after 15 turns`) is the
  only in-condition backstop.
- **`/clear` clears any active goal.** The work commands do not `/clear` mid-flow, so
  the goal survives the whole run.
- **Pairs with auto mode** for unattended per-turn execution (complementary, not
  required).

## Timing: design time vs execution time

This change lives strictly at **execution (implementation) time**:

- **Design time (enrichment)** — `/gh:enrich` / `/fj:enrich` author the spec and
  acceptance criteria into the issue body. `/goal` plays **no role** here.
- **Execution time (implementation)** — `/gh:work` / `/fj:work` read the issue, plan,
  worktree, SDD-execute, then converge via `/goal`.

Data flow: **design time *produces* the AC → execution-time `/goal` *consumes* them as
its completion condition.**

## Scope

- **In scope:** `claude/commands/gh/work.md` and `claude/commands/fj/work.md`
  (config-repo only).
- **Out of scope:** the CI `agent-implement.yml` pipeline (headless, multi-agent,
  Claude-only + version/trust friction — deliberately excluded); design/enrichment
  time; the `opencode` / `copilot` agents (no `/goal`).

## Design

### Integration model: option (b) — verification/convergence gate

SDD remains the executor (step 5 unchanged), honoring the user's global mandate to use
subagent-driven-development for plan execution. `/goal` is layered **after** SDD as the
step-5→6 gate. It composes with SDD rather than competing for control of the loop.

### Step 6 (revised), both commands

Replace the current step 6 with two sub-steps:

1. After SDD reports the plan done, the orchestrator **runs the final verification
   itself** (tests, lint) so the evidence lands in the **main** transcript — not buried
   in a subagent summary the evaluator cannot see.
2. Set a `/goal` whose condition is the issue's AC, let it converge, then stop and tell
   the user it's ready for `/wt:finish` (still **do not merge**).

### Condition template

```
/goal The acceptance criteria of issue #N hold, demonstrated in THIS conversation:
<paste/summarize the issue's acceptance criteria>. Tests were written first and are
green (TDD), lint is clean, the working tree is committed on the issue branch, and the
PR is ready with "Closes #N". Surface the actual command output as proof. Or stop
after 15 turns.
```

- **AC source:** the issue body read in step 1 (design-time output). If the issue has
  no explicit AC (un-enriched), the orchestrator derives a measurable condition from
  the plan's success criteria instead.
- **Turn bound:** default **15** — generous enough to close real gaps after SDD,
  bounded enough to avoid runaway local cost.
- **TDD reinforcement:** the condition restates "tests written first and green" so the
  independent check reinforces the non-negotiable global TDD constraint instead of
  bypassing it.

### Requirements note (documented in each command)

Needs Claude Code **v2.1.139+**, a trusted workspace, and hooks enabled
(`/goal` is unavailable under `disableAllHooks` / `allowManagedHooksOnly`). All true
locally. `/goal` pairs with **auto mode** for unattended per-turn runs.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| **Tool-blind evaluator** judges blind if test/lint output is only inside subagents | Orchestrator runs final verification in the main loop (step 6.1); condition demands evidence "in THIS conversation" |
| **Runaway loop / cost** | `or stop after 15 turns` clause; interactive run is Ctrl-C-able |
| **Premature "yes"** on weak evidence | Condition requires *actual command output as proof*, plus explicit green-tests / clean-lint / committed-tree sub-conditions |
| **Redundancy with SDD's own task loop** | `/goal` is positioned as the *verification* gate, not a second executor — it only fires after SDD completes |

## Alternatives considered (not chosen)

- **(a) Wrap the whole execution** — let `/goal` drive steps 5–6. Rejected: competes
  with SDD for loop control and duplicates SDD's task iteration.
- **(c) Lightweight mode for trivial issues** — skip plan+SDD, just `/goal <AC>`.
  Noted as a possible future secondary mode; not part of this design.
- **CI `agent-implement.yml` adoption** — rejected for now: Claude-only, version/trust
  gates, and partly duplicates the real CI lint/test gate that already runs on the PR.

## Next step

When ready to implement: `superpowers:writing-plans` → edit the two command files →
relink via `/update-commands`. No code changes are made by this spec.
