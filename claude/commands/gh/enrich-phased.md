---
description: Phased /gh:enrich — spec → /clear → plan → /clear → issue body, isolated context per phase
---

Like `/gh:enrich`, but runs each heavy phase in its **own fresh context**, with a
`/handoff` + `/clear` between phases so brainstorm context doesn't bleed into
plan-writing and plan context doesn't bleed into the issue update. Use this instead
of `/gh:enrich` when the topic is large or the session is already long.

You **cannot** run `/clear` yourself — it's the user's keystroke. So this command is
a **re-entrant state machine**: it runs one phase, records progress, writes a resume
handoff, and stops; after the user `/clear`s and resumes, it picks up the next phase.

## State

Track progress in `.claude/enrich-phased.state` (create `.claude/` if needed), a few
`key=value` lines: `issue=`, `phase=`, `spec=`, `plan=`. This file is the source of
truth for which phase runs next.

On invocation:

1. If an issue number was passed as an argument (strip any leading `#`), start a new
   run: write `issue=<N>` and `phase=spec`.
2. Else read `.claude/enrich-phased.state` and continue from its `phase`. If no
   argument and no state file, tell the user there's nothing to resume and stop.

Then dispatch to the matching phase below.

## Phase `spec`

1. `gh issue view <issue> --comments`. If the issue is closed, already has
   `ai-implement`, or is `🧊 parked`, stop and say so.
2. Assess readiness (acceptance criteria + scope + no blocking unknowns). If it's
   already complete, say so, suggest `/gh:implement <issue>`, clear the state file,
   and stop.
3. Invoke **superpowers:brainstorming** with the issue as context. Follow it
   end-to-end — clarifying questions, approaches, design sections, the spec
   self-review, and the **user approval gate**. Save the spec to the repo's tracked
   specs dir (see *Choosing a tracked path*), commit it, and record `spec=<path>`.
4. **Phase boundary** (see *Between phases*): set `phase=plan`, hand off, stop.

## Phase `plan`

1. Re-open the spec at `spec=` to re-establish context.
2. Invoke **superpowers:writing-plans** to produce the task-by-task implementation
   plan in the repo's tracked plans dir. Commit it and record `plan=<path>`.
3. **Push** so both spec and plan are on the remote (the agent-pipeline checks them
   out): `git push`. Verify it succeeded.
4. **Phase boundary:** set `phase=issue`, hand off, stop.

## Phase `issue`

1. Replace the issue body (`gh issue edit <issue> --body-file …`) with:
   - the original description (keep it for humans),
   - an `## Acceptance Criteria` section as a `- [ ]` checklist,
   - a `## Spec & Implementation Plan` section linking the **relative paths** to
     `spec=` and `plan=`, plus the line: _"Read the plan before writing any code — it
     contains the full task breakdown, file structure, TDD steps, and exact code."_
2. Push if anything else is pending.
3. **Done:** delete `.claude/enrich-phased.state` and `.claude/handoff.md`. Print the
   issue URL, the spec and plan paths, and: _"Issue is ready — run
   `/gh:implement <issue>` to trigger the agent-pipeline."_

## Between phases (handoff protocol)

At each phase boundary, before stopping:

1. Ensure the phase's artifact is committed (and pushed where the phase says so).
2. Update `.claude/enrich-phased.state` with the new `phase` and any new path.
3. Write `.claude/handoff.md` — a short, self-contained resume prompt that names the
   issue, the next phase, the spec/plan paths so far, and says: **"Resume by running
   `/gh:enrich-phased` (no argument) — it will continue at phase `<next>` from
   `.claude/enrich-phased.state`."** The `SessionStart(clear)` hook auto-injects this
   file, so after `/clear` the user only needs to say `go` (or `/pickup`).
4. Copy that resume prompt to the clipboard (`clip.exe` / `pbcopy` / `wl-copy` /
   `xclip` — whichever exists).
5. Tell the user: phase done, artifact path, and **"run `/clear`, then `go` (or
   `/pickup`) to continue."** Note you cannot run `/clear` yourself. Then stop.

## Choosing a tracked path

The agent-pipeline can only read files that are **committed and not git-ignored**.
Some repos `.gitignore` the superpowers docs dir. So before writing a spec/plan:

- Pick an existing **tracked** specs/plans dir if present (e.g.
  `docs/ai-notes/specs` + `docs/ai-notes/plans`, or `docs/superpowers/specs` +
  `…/plans` **only if not ignored**).
- Never write to a path that `git check-ignore -q <path>` reports as ignored — if the
  default target is ignored, fall back to `docs/ai-notes/{specs,plans}`.
- Confirm with `git status`/`git ls-files` that the committed file is actually tracked
  before the push phase relies on it.

## Tools

`gh` (issue read/edit), `git` (commit/push, `check-ignore`), **superpowers:brainstorming**,
**superpowers:writing-plans**, and the `/handoff`-style `.claude/handoff.md` +
`SessionStart(clear)` hook for cross-`/clear` resume.

---

If you run into blockers (ignored docs dir, push auth, brainstorming/writing-plans
unavailable, state file lost), find a solution and update this command for the future.
