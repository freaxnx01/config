---
description: List my custom slash commands (user + project), grouped
---

List **my custom** slash commands — not the built-ins or plugin-provided ones.

Scan both command directories:
- user/global: `~/.claude/commands/`
- this project: `./.claude/commands/` (only if it exists)

For every `*.md` file (recurse into subdirs, skip any `README.md`), derive the
command name from its path — `foo.md` → `/foo`, and `ns/foo.md` → `/ns:foo` — and
read its `description:` front-matter. Prefer one shell pass over reading files
individually, e.g.:

```bash
for d in ~/.claude/commands ./.claude/commands; do
  [ -d "$d" ] || continue
  find "$d" -name '*.md' ! -name 'README.md' | while read -r f; do
    name=$(printf '%s' "${f#"$d"/}" | sed 's/\.md$//; s#/#:#g')
    desc=$(sed -n 's/^description: *//p' "$f" | head -1)
    printf '/%s — %s\n' "$name" "$desc"
  done
done
```

Present grouped by **source** (User vs Project), and within each keep namespaced
families together (all `/gh:*`, etc.). Show `/<name> — <description>`, sorted
sensibly, and give the total count. If a directory is missing or empty, say so in
one line.
