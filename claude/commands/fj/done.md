---
description: Recently implemented (closed) Forgejo issues
---

List recently implemented issues in the current Forgejo repo — closed issues, most
recently closed first.

## Forgejo access

Target the homelab Forgejo (`git.home.freaxnx01.ch`) via **`tea`** (login
`git-home`). `tea issues list --state closed` works from inside the clone:

```bash
tea issues list --login git-home --state closed --fields index,title,updated,labels 2>/dev/null
```

For precise "closed at" ordering, query the API and sort by `closed_at`:

```bash
url=$(git remote get-url origin); url=${url%.git}
repo=$(echo "$url" | sed -E 's#.*[:/]([^/]+/[^/]+)$#\1#')
tea api --login git-home "repos/$repo/issues?state=closed&type=issues&limit=30&sort=updated&order=desc" \
  | python3 -c '
import sys,json
rows=[i for i in json.load(sys.stdin)]
rows.sort(key=lambda i:i.get("closed_at") or "", reverse=True)
for i in rows:
    labels=[l["name"] for l in i.get("labels") or []]
    print(i["number"],"|",i["title"],"|",i.get("closed_at"),"|",",".join(labels) or "-")'
```

> **Forgejo has no `stateReason`** (no GitHub-style "completed" vs "not planned"
> distinction) — a closed issue is just closed. So, unlike `/gh:done`, this can't
> split completed from not-planned. If you need that signal, infer it from labels
> (e.g. a `wontfix`/`duplicate` label) and list those separately.

Compact table: number, title, when closed (relative), labels. Concise.
