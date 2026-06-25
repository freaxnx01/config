---
description: Pre-review PRs against their issue's AC, then trigger the right agent (@copilot/@claude) to fix
argument-hint: "[PR numbers, e.g. 83 84 — or empty for all open non-merged PRs]"
---

Pre-review open pull request(s) in the current repo, post the review, and — only
when there are actionable fixes — nudge the agent that owns the PR to address them.

## Which PRs

`$ARGUMENTS` is an optional space-separated list of PR numbers. If empty, review
every open PR that still needs attention: `gh pr list --state open --json
number,title,author,isDraft,headRefName` — include drafts (agent PRs are usually
drafts), but skip a PR that is already approved with no open threads. Always say
which PRs you picked before starting.

## Reviewing (one reviewer per PR, in parallel)

For **each** PR, dispatch a subagent (parallel when there are 2+ — one per PR) that
does a real review, not a diff skim:

1. **Find the linked issue** — from the PR body (`Closes #N` / `implements #N`) or
   the branch name; `gh pr view <N> --json title,body,files,headRefName` +
   `gh pr diff <N>`.
2. **Read the actual source**, not just the diff — verify claims in context.
3. **Review focus, in priority order:**
   - **Correctness bugs** — logic errors, regressions, broken behavior.
   - **Acceptance-criteria coverage** — walk the linked issue's checklist; mark each
     met / partial / missing.
   - **Project conventions** — read `CLAUDE.md`; honor the stack rules (e.g. for
     .NET here: `ProblemDetails` for all errors, `IStringLocalizer` for UI strings,
     `WebApplicationFactory` integration tests, no swallowed exceptions, no hardcoded
     test returns, non-root Docker final stage).
   - **Security** — secrets, header logging, auth, CORS, input validation.
   - **Quality** — reuse, simplification, dead code, scope creep.
4. **Return** a tight report: size, a **verdict** (`Approve` / `Approve-with-nits` /
   `Changes-requested`), findings grouped **Blocking** / **Should-fix** / **Nits**
   (each with `file:line` + one line), then an **AC coverage** checklist. No file dumps.

## Posting the review

Post each review as a **comment-type** review (works on drafts; never auto-approve):

```
gh pr review <N> --comment --body-file <file>
```

Lead the body with the verdict. Keep it to the structured findings + AC coverage.

## Triggering the owning agent (only if fixes are needed)

Skip this entirely for a clean `Approve`. For `Changes-requested` or
`Approve-with-nits` **with actionable items**, post a **second, separate** comment
(not the review) addressed to the agent, with a concise **numbered** fix list (the
blocking items first).

Pick the mention from the PR's owner — `gh pr view <N> --json author,assignees,headRefName`:

- `app/copilot-swe-agent` → **`@copilot`**.
- `app/anthropic-code-agent` (assignee *Claude*, branch `claude/…`) → Claude's agent.

**Learned default — prefer `@copilot`.** In practice `@copilot` is the reliable
trigger: it reacts (👀) within a minute and starts a session, and it can **take
over any PR**, including ones Claude's agent opened. A bare `@claude` mention
registers in the timeline but the native Anthropic agent does **not** reliably
wake from a PR comment. So:

- Copilot-owned PR → `@copilot`.
- Claude-owned PR → first choice is still to hand it to **`@copilot`** ("the agent
  that opened this hasn't picked up the review — can you take it over and address
  the feedback?"). Use `@claude` only if the user has confirmed the Anthropic agent
  is responsive in this repo, and fall back to `@copilot` if no 👀 reaction appears.
- If a repo defines its own `.github/workflows/*claude*.yml`, that's a self-hosted
  `@claude` Action — then `@claude` is genuinely the trigger; check for it first.

Reformat code-fence/backtick content safely for a shell `--body` (or use a body file).

## After

Print, per PR: number, URL, verdict, and whether an agent was pinged (and which
mention). Note that Copilot pushes to the **existing branch**, so PR numbers don't
change and commit authorship will be mixed. Don't merge anything.

If there's no `gh`/repo context, say so and stop.
