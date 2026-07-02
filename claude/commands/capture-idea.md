---
description: Capture a fuzzy idea into the current repo's docs/ideas.md — zero friction, no evaluation
argument-hint: <the idea in a sentence>
---

Capture the idea below into `docs/ideas.md` for the **current repo**. Just record
it so it is not lost — do **not** evaluate, estimate, expand, or create an issue.
Evaluation is a separate step.

Idea: $ARGUMENTS

## What to do

1. Determine the idea text. If `$ARGUMENTS` is empty, use my most recent message.
   A single clear sentence is enough — do not ask questions.
2. Derive a short **title** (≤6 words) and a one-line **value** (why it matters).
   If value isn't obvious, restate the title — do not interrogate me.
3. Append the entry with this self-contained helper (matches the `docs/ideas.md`
   schema: one H2 per idea; ` · ` separators verbatim so a later status update can
   match `id: <id> ·`; unique id = `<date>-<slug>`, numeric suffix on collision):

   ```bash
   file="docs/ideas.md"; title="<title>"; value="<value>"; body="<optional body>"
   today="$(date +%F)"
   slug="$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')"
   [ -n "$slug" ] || slug="idea"
   id="${today}-${slug}"; base="$id"; n=2
   mkdir -p "$(dirname "$file")"
   [ -f "$file" ] || printf '# Ideas\n' > "$file"
   while grep -qF "id: $id ·" "$file"; do id="${base}-${n}"; n=$((n + 1)); done
   {
     printf '\n## %s\n' "$title"
     printf -- '- id: %s · captured: %s · status: raw\n' "$id" "$today"
     printf -- '- value: %s\n' "$value"
     [ -n "$body" ] && printf '%s\n' "$body"
   } >> "$file"
   printf '%s\n' "$id"
   ```

4. Confirm with the returned id and the file path. Stop.

## Rules

- Only ask a clarifying question if the title would otherwise be genuinely
  ambiguous (e.g. a one-word message). Default to capturing.
- Never create a GitHub/Forgejo issue here. Never modify code.
- One idea per invocation unless I clearly list several — then append each.
