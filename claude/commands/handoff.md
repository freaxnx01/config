---
description: Save current phase to an MD file + a resume prompt, ready to /clear
---

Prepare a clean context handoff so I can `/clear` and resume cold. Do all of this,
then stop:

1. **Persist the artifact.** Identify the current phase's artifact — the spec or
   the implementation plan. If a spec/plan markdown file already exists for this
   work, use it; otherwise write the current spec or implementation plan to a
   markdown file at a sensible path (e.g. `docs/` or the repo's plans dir).
   Make it complete enough to resume from cold (decisions made, what's done, what's
   next). Report the path.

2. **Write the resume prompt.** Create `.claude/handoff.md` (make `.claude/` if
   needed) containing a short, self-sufficient prompt that:
   - names the **exact path** to the artifact from step 1,
   - states the current phase and the next step,
   - instructs to resume using `superpowers:subagent-driven-development` for any
     implementation.

3. **Clipboard fallback.** Copy that same resume prompt to the system clipboard,
   using whichever tool exists: `clip.exe` (WSL2/Windows), `pbcopy` (macOS),
   `wl-copy` or `xclip` (Linux).

4. **Tell me what to do next.** End by printing the artifact path and this exact
   instruction: run `/clear`, then `/pickup` (or paste the clipboard) to resume.
   Note that you cannot run `/clear` yourself — that keystroke is mine.

Keep the resume prompt to a few lines but self-contained.

> **Related:** `/handoff` saves *one* in-flight phase for a `/clear`-and-resume. To
> capture *all* the session's loose ends instead, use `/wrap-up` → `/todo`.
