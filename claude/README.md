# Claude Code shared partials

Importable fragments for your **user-level** `CLAUDE.md` (the global one, not a
project's). Keeping them here means every machine version-controls the same rules
and picks up changes with a `git pull`.

| File | What it does |
|------|--------------|
| [`task-checklist.md`](task-checklist.md) | Makes Claude present action items it hands back to you as `- [ ]` Markdown checkboxes. |
| [`skill-authoring.md`](skill-authoring.md) | When creating or editing a skill, makes it **self-improving** — appends a "fix blockers and update yourself" instruction to the skill body (plus the don't-be-prescriptive / mention-tools rules). |

> Looking for **slash commands** (`/loose-ends`, `/clear-check`)? Those live in
> [`commands/`](commands/) — they're installed via symlink, not `@`-imported.

## Setup in a new environment

### Recommended — one command

The repo ships an idempotent setup script that clones (or pulls) the repo at the
canonical path AND maintains an `@`-includes marker block in `~/.claude/CLAUDE.md`:

```bash
curl -fsSL https://raw.githubusercontent.com/freaxnx01/config/main/setup/00-claude-partials.sh | bash
```

(Or, if you've already cloned the repo, run
`~/repos/github/freaxnx01/public/config/setup/00-claude-partials.sh`.)

It's safe to re-run anytime — same script keeps existing machines current after
a `git pull` in this repo. It also **migrates** any free-floating `@`-include
lines for the managed partials into a single marker-bracketed block, so the file
stays tidy.

### Manual (if you prefer)

1. **Clone this repo** (if not already present) somewhere stable, e.g. under your
   home dir so `~` resolves to it:

   ```bash
   git clone https://github.com/freaxnx01/config.git ~/repos/github/freaxnx01/public/config
   ```

2. **Find your user-level CLAUDE.md** — it lives at `~/.claude/CLAUDE.md`
   (Windows: `%USERPROFILE%\.claude\CLAUDE.md`). Create it if it doesn't exist.

3. **Add an `@` import line** pointing at the partial. The path must resolve in
   *this* environment — `~` expands to the home dir on both WSL2/Linux and Windows:

   ```text
   @~/repos/github/freaxnx01/public/config/claude/task-checklist.md
   ```

   If you cloned the repo somewhere else, use that absolute path instead
   (e.g. `@C:\Develop\Repos\config\claude\task-checklist.md` on native Windows).

   > Imports can sit anywhere in the file. Placing it near the top keeps it obvious.

## Verify it loaded

- Start a **new** Claude Code session and run `/memory`. The imported file should
  appear as a nested entry under your user `CLAUDE.md`. If it doesn't, the import
  path didn't resolve — fix the path in step 3.

## Verify the behavior

- Ask something that makes Claude hand you action items, e.g.
  *"What do I need to do to deploy this?"* — the steps should come back as `- [ ]`
  checkboxes, **unprompted**.
- Negative check: a pure-information question (*"How does OAuth work?"*) should
  **not** force checkboxes — the rule is scoped to action items, not all output.

If `/memory` shows the file but checkboxes don't appear, it's a model-adherence
gap, not a setup problem — strengthen the wording in `task-checklist.md`.
