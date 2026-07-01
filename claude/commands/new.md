---
description: Create an issue from notes, labeled needs-enrichment — auto-routes to GitHub or Forgejo by remote
argument-hint: <notes describing the issue>
---

Route to the forge-specific **new** command based on the `origin` remote host, then
follow it exactly. This command holds no logic of its own — `/gh:new` and `/fj:new`
remain the single source of truth.

## Detect the forge (generic host-matching)

```bash
# Host from origin, handling https://, ssh://, and scp-style git@host:path remotes
host=$(git remote get-url origin 2>/dev/null | sed -E 's#^[a-zA-Z]+://##; s#^[^@/]*@##; s#[:/].*##')
if gh auth token --hostname "$host" >/dev/null 2>&1; then
  echo "github  ($host)"     # a GitHub / GHES host gh is logged into
elif tea logins list 2>/dev/null | grep -qiF "$host"; then
  echo "forgejo ($host)"     # matches a tea (Forgejo/Gitea) login
elif [ "$host" = "github.com" ]; then
  echo "github  ($host)"     # fallback: canonical GitHub host, even if gh isn't authed
else
  echo "unknown ($host)"
fi
```

## Then

- **github** → read and follow `~/.claude/commands/gh/new.md` (i.e. run `/gh:new`).
- **forgejo** → read and follow `~/.claude/commands/fj/new.md` (i.e. run `/fj:new`).
- **unknown** → report the detected host and that no authed GitHub or Forgejo login
  matched it; point at `gh auth login` / `tea login add`. Don't guess a forge.

The target command creates an issue from notes — supply it with these notes:

$ARGUMENTS

Announce the chosen forge in one line (e.g. `→ GitHub (github.com)`), then carry out
that command.

---

If detection misfires (new host, an SSH `Host` alias that hides the real domain,
`gh`/`tea` not on PATH), fix the snippet here and update this command for the future.
