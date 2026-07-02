# Design — Clarify the two save-and-resume command pairs

**Issue:** #33 — *Necessary or obsolete: `/wrap-up`→`/todo` vs `/handoff`→`/pickup` — clarify or consolidate the two save-and-resume pairs*

**Date:** 2026-07-02

## Decision

**Keep both pairs. Document the distinction — do not merge, do not deprecate.**

Both pairs persist session state to a file so work can resume later, which is why
they *look* redundant. In practice they answer different questions and differ on four
load-bearing axes, so consolidating them would lose capability rather than remove
duplication.

## Why they are genuinely distinct

| Axis | `/wrap-up` → `/todo` | `/handoff` → `/pickup` |
|---|---|---|
| **Granularity** | *Many* loose ends across the whole session (checkbox list, grouped by topic) | *One* in-flight phase artifact (the current spec or plan) |
| **Boundary it serves** | End-of-session / resume next day | Mid-task `/clear` to shed context bloat and continue the *same* task cold |
| **Where it's saved & travel** | `TODO.md` at repo root — committed & pushed → durable, cross-machine | `.claude/handoff.md` — written locally + copied to clipboard, not committed → ephemeral, same-machine |
| **Automation** | No hook | Pairs with the `SessionStart(clear)` handoff-resume hook that auto-surfaces the resume prompt |
| **Resume style** | Shows a checklist, asks which item to tackle | Continues one task from the exact next step, subagent-driven |

Short version of the mental model:

- **`/wrap-up` → `/todo`** answers *"what were all the threads I left dangling?"* —
  a session-scoped, multi-topic checklist that survives across machines because it's
  committed.
- **`/handoff` → `/pickup`** answers *"I'm deep in one task and need to `/clear`
  without losing my place."* — a phase-scoped, single-artifact resume tuned for the
  `/clear` boundary and the auto-surface hook.

Merging would force session-level checklists and mid-task phase-resume into one
command and would have to reconcile the committed-vs-ephemeral persistence split,
which is exactly what makes each pair fit its job. Deprecating either drops a distinct
capability.

## Scope of the change (documentation only)

No command behaviour changes. Two doc surfaces:

### 1. `claude/commands/README.md` — add a "When to use which" subsection

Place it in the **Phase handoff** area / near the existing
`### The /handoff → /clear → /pickup flow` section so both pairs are contrasted in one
place. Content:

- A one-paragraph framing of the two questions each pair answers.
- The four-axis comparison table above (or a trimmed version of it).
- An explicit pointer that `TODO.md` is committed & pushed (cross-machine) while
  `.claude/handoff.md` is local + clipboard + hook (same-machine, ephemeral). This
  also connects to the cross-machine concern tracked in #34, without resolving it
  here.

### 2. One-line cross-reference in each of the four command files

Add a single pointer line to each command's body so the distinction is visible at the
point of use (front-matter `description:` unchanged):

- `claude/commands/wrap-up.md` → note: for resuming *one* in-flight task across a
  `/clear`, use `/handoff` instead.
- `claude/commands/todo.md` → note: this resumes a whole-session checklist; to
  continue a single task from `/handoff`, use `/pickup`.
- `claude/commands/handoff.md` → note: this saves *one* in-flight phase; to capture
  all session loose ends instead, use `/wrap-up`.
- `claude/commands/pickup.md` → note: this continues a single handed-off task; to see
  the whole-session checklist, use `/todo`.

Wording is illustrative — keep each to one terse line consistent with the file's
existing voice.

## Out of scope

- Whether `.claude/handoff.md` should be committable/syncable across machines — that
  is issue **#34** and is intentionally not decided here.
- Any change to command behaviour, the hook, or `settings.json`.

## Acceptance criteria

- [ ] `claude/commands/README.md` has a "when to use which" subsection contrasting the
  two pairs, including the persistence/travel difference.
- [ ] Each of `wrap-up.md`, `todo.md`, `handoff.md`, `pickup.md` carries a one-line
  cross-reference pointing at its counterpart pair.
- [ ] No command behaviour or front-matter `description:` changes.
- [ ] Docs render correctly (valid Markdown table, working relative links).

## Testing

This is a docs-only change with no runtime surface. Verification is a doc review:
render/read the README section and the four command files, confirm the table is valid
Markdown, links resolve, and each cross-reference names the correct counterpart
command. No automated test harness applies.
