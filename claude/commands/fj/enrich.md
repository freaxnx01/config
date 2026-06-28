---
description: Enrich a Forgejo issue with a spec and implementation plan, then update the issue body
argument-hint: <issue number>
---

Enrich Forgejo issue #$ARGUMENTS (strip any leading `#`) so it is ready to
implement. Everything the implementer needs must end up in the issue **body** (+ the
committed spec/plan it links to).

## Forgejo access

Target the homelab Forgejo (`git.home.freaxnx01.ch`) via **`tea`** (login
`git-home`):

```bash
url=$(git remote get-url origin); url=${url%.git}
repo=$(echo "$url" | sed -E 's#.*[:/]([^/]+/[^/]+)$#\1#')
```

## Step 1 — Read the issue

```bash
tea issues $ARGUMENTS --login git-home
tea api --login git-home "repos/$repo/issues/$ARGUMENTS/comments"
```

If the issue is closed or `🧊 parked`, stop and say so.

## Step 2 — Assess readiness

Judge whether the issue already has all three:

- **Acceptance criteria** — concrete, testable conditions
- **Scope / spec** — what to build, enough to start without guessing
- **No blocking unknowns** — no open design questions or TBDs the implementer can't
  resolve from the codebase

If it's already complete, tell me and suggest running `/fj:work $ARGUMENTS` directly.
Stop here.

## Step 3 — Brainstorm spec

Invoke **superpowers:brainstorming** with the issue as context. The goal is a
validated spec saved to a **tracked** specs dir (see *Choosing a tracked path*) and
committed. Follow the brainstorming skill end-to-end (clarifying questions,
approaches, design sections, spec self-review, user approval gate).

## Step 4 — Write implementation plan

After brainstorming exits, invoke **superpowers:writing-plans** to produce the full
task-by-task plan in a tracked plans dir and commit it.

## Step 5 — Push to remote

Commit and push both the spec and plan before touching the issue body — the body
references these files by path:

```bash
git push
```

Verify the push succeeded before proceeding.

## Step 6 — Update the issue body

Replace the issue body via API PATCH — use the **typed** field `-F` so it reads the
file (`-f` would store the literal string `@bodyfile.md`; `tea issues edit` has no
body flag):

```bash
tea api -X PATCH "repos/$repo/issues/$ARGUMENTS" -F body=@bodyfile.md
```

The new body has:

1. The original description (keep it — context for humans)
2. An `## Acceptance Criteria` section with the approved AC as a `- [ ]` checklist
3. A `## Spec & Implementation Plan` section with relative paths to the spec and plan
   files (linked as markdown) plus: _"Read the plan before writing any code — it
   contains the full task breakdown, file structure, TDD steps, and exact code to
   produce."_

## Step 7 — Confirm

Print the issue URL, the spec and plan paths, and: _"Issue is ready — run
`/fj:work $ARGUMENTS` to implement it locally."_

> When the self-hosted **Forgejo Actions** agent-pipeline exists (future tier), this
> final pointer becomes "apply the `ai-implement` label / run `/fj:implement`" to
> trigger the runner instead — update this step then.

## Choosing a tracked path

A spec/plan is only useful if it's **committed and not git-ignored**. Pick an
existing tracked specs/plans dir; never write to a path that `git check-ignore -q
<path>` reports as ignored — fall back to `docs/ai-notes/{specs,plans}`. Confirm with
`git ls-files` that the committed file is tracked before the push step relies on it.

---

If you run into blockers (brainstorming/writing-plans unavailable, push auth fails,
the issue-body PATCH is rejected, ignored docs dir), find a solution and update this
command for the future.
