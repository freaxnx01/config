# TDD Enforcement in gh:work, gh:implement, gh:assign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enforce TDD unconditionally on all three implementation paths by adding a global constraint to `gh:work` and posting a structured TDD contract comment in `gh:implement` and `gh:assign`.

**Architecture:** Three surgical edits to Markdown slash-command files in `claude/commands/gh/`. No code compilation or automated tests — verification is grep-based confirmation that the additions are present and correctly placed, followed by manual read-through. After each edit, the file is copied to `~/.claude/commands/gh/` (the runtime location, which holds copies not symlinks).

**Tech Stack:** Markdown, `gh` CLI (for the comment blocks added to implement/assign), bash `cp` for syncing.

## Global Constraints

- TDD is a non-negotiable global constraint — include this verbatim in the Global Constraints section of any implementation plan.
- All edits are in `claude/commands/gh/` (repo source). Each task also copies the edited file to `~/.claude/commands/gh/` so it takes effect immediately.
- The TDD contract comment text must be identical across `gh:implement` and `gh:assign`.
- Conventional Commits format for all commit messages.
- Edit the canonical repo files; never edit `~/.claude/` files directly.

---

### Task 1: Add TDD global constraint to `gh/work.md`

**Files:**
- Modify: `claude/commands/gh/work.md` (step 3 in the command body)
- Sync: copy to `~/.claude/commands/gh/work.md`

**Interfaces:**
- Consumes: nothing from other tasks
- Produces: updated `work.md` consumed by Task 3's commit

**Context:** `gh:work` calls `superpowers:writing-plans` in step 3, then `superpowers:subagent-driven-development` in step 5. TDD enforcement flows through the plan's Global Constraints section into each implementer subagent's task brief. The implementer template already has a conditional TDD evidence block; making TDD a global constraint makes it unconditional.

Current step 3 text (exact):
```
3. Use **superpowers:writing-plans** to produce an implementation plan (markdown).
```

Target step 3 text:
```
3. Use **superpowers:writing-plans** to produce an implementation plan (markdown).
   TDD is a non-negotiable global constraint — include it verbatim in the plan's
   Global Constraints section: "Use Test-Driven Development for every task: write
   a failing test first, watch it fail, implement minimally to pass, verify green."
```

- [ ] **Step 1: Read the current file**

```bash
cat claude/commands/gh/work.md
```

Confirm step 3 is exactly: `3. Use **superpowers:writing-plans** to produce an implementation plan (markdown).`

- [ ] **Step 2: Apply the edit**

In `claude/commands/gh/work.md`, replace step 3 with:

```
3. Use **superpowers:writing-plans** to produce an implementation plan (markdown).
   TDD is a non-negotiable global constraint — include it verbatim in the plan's
   Global Constraints section: "Use Test-Driven Development for every task: write
   a failing test first, watch it fail, implement minimally to pass, verify green."
```

- [ ] **Step 3: Verify the edit is present**

```bash
grep -A3 "writing-plans" claude/commands/gh/work.md
```

Expected output includes:
```
Use **superpowers:writing-plans** to produce an implementation plan (markdown).
   TDD is a non-negotiable global constraint
```

- [ ] **Step 4: Sync to ~/.claude**

```bash
cp claude/commands/gh/work.md ~/.claude/commands/gh/work.md
```

- [ ] **Step 5: Verify sync**

```bash
diff claude/commands/gh/work.md ~/.claude/commands/gh/work.md && echo "in sync"
```

Expected: `in sync`

- [ ] **Step 6: Commit**

```bash
git add claude/commands/gh/work.md
git commit -m "feat(commands): enforce TDD as global constraint in gh:work"
```

---

### Task 2: Add TDD contract comment step to `gh/implement.md`

**Files:**
- Modify: `claude/commands/gh/implement.md`
- Sync: copy to `~/.claude/commands/gh/implement.md`

**Interfaces:**
- Consumes: nothing from other tasks
- Produces: the TDD contract comment text (identical text reused in Task 3)

**Context:** `gh:implement` checks preconditions then applies the `ai-implement` label. The agent-pipeline fetches the issue (including comments) via `gh issue view --comments` and builds the prompt. The TDD contract comment must be posted after precondition checks pass and before the label is applied. The new step sits between "## Apply the label" and the `gh label create` command, under a new `## Post TDD contract` heading.

The TDD contract comment to post:

```
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

The `gh issue comment` command to post it (with `<N>` replaced by the actual issue number at runtime):

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

- [ ] **Step 1: Read the current file**

```bash
cat claude/commands/gh/implement.md
```

Locate the `## Apply the label` section. The new `## Post TDD contract` section will be inserted immediately before it.

- [ ] **Step 2: Apply the edit**

Insert the following block into `claude/commands/gh/implement.md` immediately before the `## Apply the label` heading:

```markdown
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

```

- [ ] **Step 3: Verify the section is present and positioned correctly**

```bash
grep -n "Post TDD contract\|Apply the label" claude/commands/gh/implement.md
```

Expected output (line numbers will vary, but `Post TDD contract` must come before `Apply the label`):
```
28:## Post TDD contract
38:## Apply the label
```

- [ ] **Step 4: Sync to ~/.claude**

```bash
cp claude/commands/gh/implement.md ~/.claude/commands/gh/implement.md
```

- [ ] **Step 5: Verify sync**

```bash
diff claude/commands/gh/implement.md ~/.claude/commands/gh/implement.md && echo "in sync"
```

Expected: `in sync`

- [ ] **Step 6: Commit**

```bash
git add claude/commands/gh/implement.md
git commit -m "feat(commands): post TDD contract comment in gh:implement before labeling"
```

---

### Task 3: Add TDD contract comment step to `gh/assign.md`

**Files:**
- Modify: `claude/commands/gh/assign.md`
- Sync: copy to `~/.claude/commands/gh/assign.md`

**Interfaces:**
- Consumes: TDD contract comment text established in Task 2 (use identical wording)
- Produces: nothing consumed by later tasks

**Context:** `gh/assign.md` checks preconditions, resolves the bot actor ID, then calls `replaceActorsForAssignable`. The TDD contract comment must be posted after precondition checks and before the GraphQL assign mutation. The command uses `<N>` as the issue number variable (set from `$ARGUMENTS`). Insert a new `## Post TDD contract` section immediately before `## Resolve the actor and assign`.

- [ ] **Step 1: Read the current file**

```bash
cat claude/commands/gh/assign.md
```

Locate the `## Resolve the actor and assign` section. The new `## Post TDD contract` section will be inserted immediately before it.

- [ ] **Step 2: Apply the edit**

Insert the following block into `claude/commands/gh/assign.md` immediately before the `## Resolve the actor and assign` heading:

```markdown
## Post TDD contract

Post a TDD requirement comment on the issue so the assigned agent reads it as part
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

Replace `<N>` with the actual issue number (from `$ARGUMENTS`).

```

- [ ] **Step 3: Verify the section is present and positioned correctly**

```bash
grep -n "Post TDD contract\|Resolve the actor" claude/commands/gh/assign.md
```

Expected output (`Post TDD contract` must come before `Resolve the actor and assign`):
```
28:## Post TDD contract
42:## Resolve the actor and assign
```

- [ ] **Step 4: Sync to ~/.claude**

```bash
cp claude/commands/gh/assign.md ~/.claude/commands/gh/assign.md
```

- [ ] **Step 5: Verify sync**

```bash
diff claude/commands/gh/assign.md ~/.claude/commands/gh/assign.md && echo "in sync"
```

Expected: `in sync`

- [ ] **Step 6: Commit**

```bash
git add claude/commands/gh/assign.md
git commit -m "feat(commands): post TDD contract comment in gh:assign before assigning"
```
