# `/goal` Execution-Time Verification Gate in gh:work & fj:work — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the manual "complete **and verified**" judgment at the end of `/gh:work` and `/fj:work` with an independent `/goal` convergence loop that runs until the issue's acceptance criteria demonstrably hold (or a 15-turn bound), then stops for `/wt:finish`.

**Architecture:** Two surgical edits to Markdown slash-command files in `claude/commands/`. Each command's final step (step 6) is rewritten to (1) run the final verification in the main conversation so the tool-blind evaluator can read it, and (2) set a `/goal` whose condition is the issue's acceptance criteria. SDD (step 5) is unchanged. No code compilation and no executable tests exist for slash-command Markdown — verification is `grep`-based confirmation that the new blocks are present and correctly placed, followed by a read-through. The runtime files in `~/.claude/commands/` are **symlinks** into this repo, so editing the canonical repo file takes effect immediately — no copy/relink step is required.

**Tech Stack:** Markdown slash commands, `grep` for verification, Conventional Commits.

## Global Constraints

- Use Test-Driven Development for every task: write a failing test first, watch it fail, implement minimally to pass, verify green. *(For these Markdown command edits there is no executable test harness; the equivalent "failing → passing" check is a `grep` that returns no match before the edit and the expected match after. No production code is written without this check.)*
- All edits are in `claude/commands/` (repo source). Runtime files in `~/.claude/commands/` are symlinks — never edit them directly; editing the repo file is live immediately.
- The revised step 6 text and the `/goal` condition template must be identical across `gh/work.md` and `fj/work.md` (only the surrounding command-specific prose differs).
- The `/goal` condition must always include the bound `Or stop after 15 turns.`
- The `/goal` condition must demand evidence "in THIS conversation" and "actual command output as proof" (the evaluator is tool-blind).
- Conventional Commits format for all commit messages.
- Out of scope: `agent-pipeline` (`agent-implement.yml`), enrichment-time commands, opencode/copilot.

---

### Task 1: Add the `/goal` verification gate to `gh/work.md`

**Files:**
- Modify: `claude/commands/gh/work.md` (step 6 + a requirements note)

**Interfaces:**
- Consumes: nothing from other tasks
- Produces: the canonical revised step-6 block + condition template, reused verbatim by Task 2

- [ ] **Step 1: Confirm the gate is absent (the "failing test")**

Run: `grep -n '/goal' claude/commands/gh/work.md`
Expected: no output (exit 1) — the gate does not exist yet.

- [ ] **Step 2: Replace step 6**

Find this exact block in `claude/commands/gh/work.md`:

```markdown
6. When implementation is complete **and verified**, stop and tell me it's ready
   for `/wt:finish` — do not merge yet.
```

Replace it with:

```markdown
6. **Verify and converge with `/goal`.** SDD reporting the plan done is not the
   same as "verified" — run the verification yourself, then let an independent
   check confirm the acceptance criteria actually hold:
   1. In the **main** conversation (not inside a subagent), run the final
      verification — the full test suite and lint — so the output lands in this
      transcript. The `/goal` evaluator is tool-blind: it only judges what you
      surface here, not what a subagent did internally.
   2. Set a goal whose condition is issue #$ARGUMENTS's acceptance criteria, then
      let it converge:

      ```
      /goal The acceptance criteria of issue #$ARGUMENTS hold, demonstrated in THIS
      conversation: <summarize the issue's acceptance criteria>. Tests were written
      first and are green (TDD), lint is clean, the working tree is committed on the
      issue branch, and the PR is ready with "Closes #$ARGUMENTS". Surface the
      actual command output as proof. Or stop after 15 turns.
      ```

      If the issue has no explicit acceptance criteria, derive a measurable
      condition from the plan's success criteria instead.
7. When the goal clears (condition met) or stops at the turn bound, stop and tell
   me it's ready for `/wt:finish` — **do not merge yet**.

> **Requires** Claude Code v2.1.139+, a trusted workspace, and hooks enabled
> (`/goal` is unavailable under `disableAllHooks` / `allowManagedHooksOnly`). Pair
> with auto mode for unattended per-turn convergence.
```

- [ ] **Step 3: Verify the gate is present (the "passing test")**

Run:
```bash
grep -nc '/goal' claude/commands/gh/work.md          # expect >= 2
grep -n 'Or stop after 15 turns' claude/commands/gh/work.md   # expect 1 match
grep -n 'v2.1.139' claude/commands/gh/work.md         # expect the requirements note
grep -n 'tool-blind' claude/commands/gh/work.md       # expect the evaluator caveat
```
Expected: each grep matches as annotated. Then read the file top-to-bottom once to confirm steps renumber cleanly (old step 6 → new steps 6 and 7) and the "Reference issue #$ARGUMENTS in commits…" closing paragraph is untouched.

- [ ] **Step 4: Commit**

```bash
git add claude/commands/gh/work.md
git commit -m "feat(gh): add /goal verification gate to gh:work"
```

---

### Task 2: Add the same gate to `fj/work.md`

**Files:**
- Modify: `claude/commands/fj/work.md` (step 6 + a requirements note)

**Interfaces:**
- Consumes: the revised step-6 block + condition template produced by Task 1 (use it verbatim)
- Produces: nothing for later tasks

- [ ] **Step 1: Confirm the gate is absent (the "failing test")**

Run: `grep -n '/goal' claude/commands/fj/work.md`
Expected: no output (exit 1).

- [ ] **Step 2: Replace step 6**

Find this exact block in `claude/commands/fj/work.md`:

```markdown
6. When implementation is complete **and verified**, stop and tell me it's ready for
   `/wt:finish` — do not merge yet.
```

Replace it with the **identical** block from Task 1, Step 2 (the `6.` / `7.` steps and the `> **Requires** …` note). The `$ARGUMENTS` token is the same in both commands; do not alter the condition text.

- [ ] **Step 3: Verify the gate is present (the "passing test")**

Run:
```bash
grep -nc '/goal' claude/commands/fj/work.md          # expect >= 2
grep -n 'Or stop after 15 turns' claude/commands/fj/work.md   # expect 1 match
grep -n 'v2.1.139' claude/commands/fj/work.md         # expect the requirements note
grep -n 'tool-blind' claude/commands/fj/work.md       # expect the evaluator caveat
```
Expected: each grep matches as annotated. Then read the file once to confirm the Forgejo-specific closing paragraph (the `issue-N-*` branch-detection note) and the `## Forgejo access` section are untouched, and steps renumber cleanly.

- [ ] **Step 4: Verify the two gates are byte-identical**

Run:
```bash
diff <(sed -n '/6\. \*\*Verify and converge/,/auto mode for unattended/p' claude/commands/gh/work.md) \
     <(sed -n '/6\. \*\*Verify and converge/,/auto mode for unattended/p' claude/commands/fj/work.md)
```
Expected: no output — the gate blocks are identical.

- [ ] **Step 5: Commit**

```bash
git add claude/commands/fj/work.md
git commit -m "feat(fj): add /goal verification gate to fj:work"
```

---

## Self-Review

**Spec coverage:**
- Integration model (b), step-5→6 gate → Tasks 1 & 2 step 2. ✓
- Condition template w/ AC + TDD + 15-turn bound → Task 1 step 2, enforced by Global Constraints. ✓
- Tool-blind mitigation (final verification in main loop; "actual command output as proof") → Task 1 step 2 sub-step 1 + condition text. ✓
- Requirements note (v2.1.139+, trust, hooks, auto mode) → Task 1 step 2 `> **Requires**` block; verified in step 3. ✓
- AC-absent fallback → Task 1 step 2. ✓
- Identical text across both commands → Global Constraints + Task 2 step 4 diff. ✓
- Out of scope (CI pipeline, enrichment, opencode/copilot) → Global Constraints. ✓

**Placeholder scan:** `<summarize the issue's acceptance criteria>` is an intentional runtime template token filled per-issue by the command, not a plan placeholder. No TBD/TODO. ✓

**Type consistency:** N/A (Markdown). Grep targets (`/goal`, `Or stop after 15 turns`, `v2.1.139`, `tool-blind`) match the text inserted in step 2 across both tasks. ✓
