---
description: Recommend how to implement an issue — gh:work / gh:assign copilot|claude / gh:implement — by complexity & readiness
argument-hint: <issue number>
---

Help me pick the **right implementation route** for issue #$ARGUMENTS (strip any
leading `#`). Read the issue, judge it, recommend one route with reasoning, then
offer to run it. Do **not** dispatch anything until I confirm.

## Step 1 — Read the issue

```bash
gh issue view <N> --comments --json number,title,state,labels,body,assignees
```
Also note any linked spec/plan files and existing PRs. If it's closed, parked
(`🧊 parked`), or already assigned to an agent, say so and stop.

## Step 2 — Readiness gate (first, non-negotiable)

An agent needs **acceptance criteria + scope + no blocking unknowns**. If the issue
is missing any, or carries `needs-enrichment` / `❓ to-be-defined`:

- Recommend **`/gh:enrich <N>`** (or **`/gh:enrich-phased <N>`** if it's large or
  spans multiple subsystems) and **stop** — don't route an unready issue to any agent.

## Step 3 — Assess the work

Judge the issue on:

- **Complexity & novelty** — mechanical/well-trodden vs. cross-cutting, architectural,
  or subtle.
- **Correctness/security sensitivity** — auth, money, data integrity, concurrency,
  migrations.
- **Breadth** — one file vs. many modules. (If it's really several independent
  subsystems, recommend decomposing into separate issues first.)
- **Locality needs** — does it need things only a local maintainer has: real secrets /
  a live DB, manual/visual verification, hardware, or back-and-forth design iteration?
- **Stack fit** — anything Copilot tends to struggle with (obscure tooling, heavy
  domain context).

## Step 4 — Map to a route

| Situation | Route | Why |
|---|---|---|
| Not ready (no AC / scope / open unknowns) | **`/gh:enrich`** then re-run | agents guess badly without AC |
| Needs local secrets, live DB, manual/visual verify, or design iteration | **`/gh:work <N>`** (local, in-session) | only you have the env; you drive it, subagent-driven |
| Ready · small/mechanical · well-trodden | **`/gh:assign <N> copilot`** | fast, reliable trigger; cheap |
| Ready · complex reasoning / architecture / subtle correctness / security | **`/gh:assign <N> claude`** *or* **`/gh:implement <N>`** | stronger reasoning where it matters |
| Want the label-pipeline (`claude.yml`) rather than a direct assignee | **`/gh:implement <N>`** | pipeline path; Claude opens a draft PR |

**How the routes differ (say this when relevant):**
- **`/gh:assign`** → hands the issue to a GitHub **coding agent** on its own branch/PR.
  Prefer **copilot** (the reliable trigger here); **claude** only when confirmed
  responsive in this repo.
- **`/gh:implement`** → applies the `ai-implement` label, which fires the repo's
  **agent-pipeline** (`claude.yml`) → Claude implements and opens a draft PR.
- **`/gh:work`** → **local, in this session**: brainstorm → plan → worktree →
  subagent-driven. Best when you want to stay in the loop or the work isn't
  cloud-friendly.

A rough rule of thumb: **mechanical → Copilot**, **needs real judgement → Claude**,
**needs your machine or your eyes → local `/gh:work`**, **not ready → enrich first**.

## Step 5 — Recommend, then offer to run

Print:
- A one-line verdict: the recommended route + the **exact command** to run.
- 1–2 sentences of reasoning tied to what you saw in the issue.
- The runner-up route and when it'd be better.

Then ask if I want you to run the recommended command now. Only run it after I confirm.

## Tools

`gh` (issue read), and the sibling commands `/gh:enrich`, `/gh:enrich-phased`,
`/gh:assign`, `/gh:implement`, `/gh:work`.

---

If you hit a blocker (issue not found, ambiguous readiness, a route that doesn't fit
the situation), reason it out, recommend the closest sensible option, and update this
command for the future.
