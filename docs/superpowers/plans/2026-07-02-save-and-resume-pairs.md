# Clarify the two save-and-resume command pairs — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Document that `/wrap-up`→`/todo` and `/handoff`→`/pickup` are distinct (keep both), so the difference is obvious in the README and at each command's point of use.

**Architecture:** Documentation-only change. Add one "when to use which" subsection to `claude/commands/README.md` and one cross-reference line to each of the four command files. No command behaviour or front-matter `description:` changes.

**Tech Stack:** Markdown only. Repo: `freaxnx01/config`. Spec: `docs/superpowers/specs/2026-07-02-save-and-resume-pairs-design.md`. Issue: #33.

## Global Constraints

- **TDD (verbatim, workflow-mandated):** "Use Test-Driven Development for every task: write a failing test first, watch it fail, implement minimally to pass, verify green." — **N/A in practice here:** this is a docs-only change with no runtime surface, so there is no failing-test cycle to run. Per-task verification is a **doc review**: valid Markdown, links resolve, wording names the correct counterpart command. This substitution is deliberate and matches the spec's Testing section.
- **Commit convention:** Conventional Commits (`docs(scope): ...`), reference `#33` in each commit.
- **Voice:** each added line matches the existing terse voice of the file it lands in; do not touch front-matter `description:` fields.
- **No behaviour changes:** only prose/table additions.

---

### Task 1: README "when to use which" subsection

**Files:**
- Modify: `claude/commands/README.md` — insert a new `### When to use which save-and-resume pair` subsection immediately **before** the existing `### The /handoff → /clear → /pickup flow` heading (around line 118).

**Interfaces:**
- Consumes: nothing.
- Produces: an anchor the command cross-refs (Task 2) conceptually point at; no code symbols.

- [ ] **Step 1 (verification-first): confirm the insertion point**

Run: `grep -n "### The \`/handoff\` → \`/clear\` → \`/pickup\` flow" claude/commands/README.md`
Expected: one match (currently line 118). Insert the new subsection just before it.

- [ ] **Step 2: insert the subsection**

Add this block immediately before the `### The /handoff → /clear → /pickup flow` heading:

```markdown
### When to use which save-and-resume pair

Both pairs persist state to a file so work can resume later, so they look
redundant — but they answer different questions and are **both kept on purpose**:

- **`/wrap-up` → `/todo`** — *"what were all the threads I left dangling?"* A
  whole-session, multi-topic checklist. `/wrap-up` writes `TODO.md` at the repo root
  and **commits & pushes** it; `/todo` reads it back, shows the unchecked items, and
  asks which to tackle. Because `TODO.md` is committed, it survives across machines.
- **`/handoff` → `/pickup`** — *"I'm deep in one task and need to `/clear` without
  losing my place."* A single in-flight phase artifact (the current spec or plan).
  `/handoff` writes `.claude/handoff.md` + copies a resume prompt to the clipboard;
  `/pickup` continues that one task from the exact next step, subagent-driven. It
  pairs with the `SessionStart(clear)` hook below.

| Axis | `/wrap-up` → `/todo` | `/handoff` → `/pickup` |
|---|---|---|
| Granularity | many loose ends across the session | one in-flight phase artifact |
| Boundary | end-of-session / next-day resume | mid-task `/clear` to shed context bloat |
| Saved to & travel | `TODO.md` at repo root — committed & pushed → cross-machine | `.claude/handoff.md` — local + clipboard, not committed → same-machine |
| Automation | none | `SessionStart(clear)` handoff-resume hook |
| Resume style | checklist, pick an item | continue one task from the next step |

> `.claude/handoff.md` is intentionally local/ephemeral today; making it syncable
> across machines is tracked separately in issue #34.

```

- [ ] **Step 3: verify Markdown + links (the doc-review "test")**

Run: `grep -n "When to use which save-and-resume pair" claude/commands/README.md && sed -n '/### When to use which/,/### The/p' claude/commands/README.md`
Expected: the new heading appears exactly once, immediately before the flow section; the table has 5 data rows and a valid header separator; no stray placeholders.

- [ ] **Step 4: commit**

```bash
git add claude/commands/README.md
git commit -m "docs(commands): add 'when to use which' save-and-resume section (#33)"
```

---

### Task 2: One-line cross-reference in each of the four command files

**Files:**
- Modify: `claude/commands/wrap-up.md` — add a pointer line at the end of the body.
- Modify: `claude/commands/todo.md` — add a pointer line at the end of the body.
- Modify: `claude/commands/handoff.md` — add a pointer line at the end of the body.
- Modify: `claude/commands/pickup.md` — add a pointer line at the end of the body.

**Interfaces:**
- Consumes: the README subsection from Task 1 (each line may reference "see the README" implicitly, but must stand alone).
- Produces: nothing downstream.

- [ ] **Step 1: add the cross-ref to `wrap-up.md`**

Append after the final `Keep it terse. No preamble.` line:

```markdown

> **Related:** `/wrap-up` captures *all* session loose ends. To save and resume a
> *single* in-flight task across a `/clear`, use `/handoff` → `/pickup` instead.
```

- [ ] **Step 2: add the cross-ref to `todo.md`**

Append after the final `If you run into blockers…` line:

```markdown

> **Related:** `/todo` resumes the whole-session checklist. To continue a single task
> saved by `/handoff`, use `/pickup` instead.
```

- [ ] **Step 3: add the cross-ref to `handoff.md`**

Append after the final `Keep the resume prompt to a few lines but self-contained.` line:

```markdown

> **Related:** `/handoff` saves *one* in-flight phase for a `/clear`-and-resume. To
> capture *all* the session's loose ends instead, use `/wrap-up` → `/todo`.
```

- [ ] **Step 4: add the cross-ref to `pickup.md`**

Append after the final `If \`.claude/handoff.md\` doesn't exist…` line:

```markdown

> **Related:** `/pickup` continues a single handed-off task. To see the whole-session
> checklist from `/wrap-up`, use `/todo` instead.
```

- [ ] **Step 5: verify all four cross-refs (doc-review "test")**

Run: `for f in wrap-up todo handoff pickup; do echo "== $f =="; grep -c "> \*\*Related:\*\*" claude/commands/$f.md; done`
Expected: each file prints `1`. Manually confirm each line names the correct counterpart pair (wrap-up→handoff/pickup, todo→pickup, handoff→wrap-up/todo, pickup→todo).

- [ ] **Step 6: commit**

```bash
git add claude/commands/wrap-up.md claude/commands/todo.md claude/commands/handoff.md claude/commands/pickup.md
git commit -m "docs(commands): cross-reference the two save-and-resume pairs (#33)"
```

---

## Self-Review

**Spec coverage:**
- Spec change #1 (README "when to use which" subsection incl. persistence/travel note + #34 pointer) → Task 1. ✓
- Spec change #2 (one-line cross-ref in each of the 4 command files) → Task 2. ✓
- Spec AC "no behaviour / description changes" → enforced in Global Constraints and both tasks only append body prose. ✓
- Spec AC "docs render correctly" → verification steps in each task. ✓

**Placeholder scan:** No TBD/TODO/"handle edge cases"; all inserted content is literal and complete. ✓

**Type consistency:** No code symbols; the only cross-artifact names are the command names (`/wrap-up`, `/todo`, `/handoff`, `/pickup`) and the file paths, used consistently. ✓
