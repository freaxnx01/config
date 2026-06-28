---
description: Recommend how to implement a Forgejo issue — enrich first, or local /fj:work — by complexity & readiness
argument-hint: <issue number>
---

Help me pick the **right implementation route** for Forgejo issue #$ARGUMENTS (strip
any leading `#`). Read the issue, judge it, recommend one route with reasoning, then
offer to run it. Do **not** dispatch anything until I confirm.

## Forgejo access

Target the homelab Forgejo (`git.home.freaxnx01.ch`) via **`tea`** (login
`git-home`).

## Step 1 — Read the issue

```bash
url=$(git remote get-url origin); url=${url%.git}
repo=$(echo "$url" | sed -E 's#.*[:/]([^/]+/[^/]+)$#\1#')
tea issues $ARGUMENTS --login git-home
tea api --login git-home "repos/$repo/issues/$ARGUMENTS/comments"
```

Note any linked spec/plan files and existing PRs. If it's closed, parked
(`🧊 parked`), or already being worked (an `issue-$ARGUMENTS-*` branch or open PR
exists), say so and stop.

## Step 2 — Readiness gate (first, non-negotiable)

An agent/implementer needs **acceptance criteria + scope + no blocking unknowns**.
If the issue is missing any, or carries `needs-enrichment` / `❓ to-be-defined`:

- Recommend **`/fj:enrich <N>`** (or **`/fj:enrich-phased <N>`** if it's large or
  spans multiple subsystems) and **stop** — don't route an unready issue.

## Step 3 — Assess the work

Judge the issue on **complexity & novelty**, **correctness/security sensitivity**
(auth, money, data integrity, migrations), **breadth** (one file vs. many modules —
if it's really several independent subsystems, recommend decomposing into separate
issues first), and **locality needs** (real secrets, a live DB, manual/visual
verification, hardware, or back-and-forth design iteration).

## Step 4 — Map to a route

| Situation | Route | Why |
|---|---|---|
| Not ready (no AC / scope / open unknowns) | **`/fj:enrich <N>`** then re-run | implementers guess badly without AC |
| Ready · anything implementable | **`/fj:work <N>`** (local, in-session) | brainstorm → plan → worktree → subagent-driven; you stay in the loop |

> **No cloud coding-agent route on Forgejo (yet).** GitHub's `/gh:assign`
> (Copilot/Claude bots) and `/gh:implement` (the `claude.yml` agent-pipeline) have
> **no native Forgejo equivalent**. The plan is to add a self-hosted **Forgejo
> Actions** pipeline (label → runner runs Claude Code → opens a PR) as a future
> tier; until that runner + `ANTHROPIC_API_KEY` secret exist, **every implementable
> issue routes to local `/fj:work`**. When the pipeline lands, add an
> `/fj:implement` row here and a model-policy step.

## Step 5 — Recommend, then offer to run

Print a one-line verdict (recommended route + exact command), 1–2 sentences of
reasoning tied to what you saw, and the runner-up. Then ask if I want you to run it.
Only run after I confirm.

---

If you hit a blocker (issue not found, ambiguous readiness, or the Forgejo Actions
pipeline becomes available and this routing table is now stale), reason it out,
recommend the closest sensible option, and update this command for the future.
