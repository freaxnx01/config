---
description: Triage a batch of test-feedback notes into Issue / TODO.md / implement-now
argument-hint: <pasted tester notes — mixed EN/DE ok; attachments as file paths>
---

Process test feedback using the `processing-test-feedback` skill: turn the raw notes
below into a per-entry decision (tracker Issue vs `TODO.md` entry vs implement-now vs
no-action), grounded in the repo's existing issues/TODO/glossary, with dedup and a
resumable worklog. Present the triage table and stop for my approval before creating,
editing, or coding anything.

If no notes are given below:
- first scan `docs/ai-notes/feedback/` for an unfinished worklog and offer to **resume** it;
- if there's nothing to resume, ask me to paste the notes.

Attachments (screenshots/videos) referenced by file path are persisted into the worklog's
assets dir; a pasted-only image can't be saved by you — ask me for the file path.

My notes:
$ARGUMENTS
