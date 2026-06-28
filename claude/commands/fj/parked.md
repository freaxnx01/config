---
description: List parked Forgejo issues (🧊 parked) — intentionally deferred, newest first
---

List open issues in the current Forgejo repo that are **parked** — i.e. carry the
`🧊 parked` label (understood but intentionally deferred) — **newest first**. These
are the issues excluded from `/fj:issues`.

## Forgejo access

Target the homelab Forgejo (`git.home.freaxnx01.ch`) via **`tea`** (login
`git-home`). Resolve `owner/name` from the clone's remote (needed for `tea api`):

```bash
url=$(git remote get-url origin); url=${url%.git}
repo=$(echo "$url" | sed -E 's#.*[:/]([^/]+/[^/]+)$#\1#')
```

## Approach

Forgejo has no GraphQL, so we can't get linked-PR state in one query. List parked
issues directly, then (optionally) annotate each with whether an **open** PR
references it, reusing the same PR-link derivation as `/fj:issues`.

```bash
# open PRs → set of referenced issue numbers (for the WIP annotation)
tea api --login git-home "repos/$repo/pulls?state=open&limit=50&type=pulls" \
  | python3 -c '
import sys,json,re
pat=re.compile(r"\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s+#(\d+)", re.I)
wip=set()
for p in json.load(sys.stdin):
    for n in pat.findall((p.get("title") or "")+" "+(p.get("body") or "")): wip.add(int(n))
open("/tmp/fj_wip.txt","w").write(" ".join(map(str,sorted(wip))))'
# parked issues, newest first — filter client-side (the labels= query param breaks
# on a label name containing a space + emoji; it isn't URL-encoded by tea api)
tea api --login git-home "repos/$repo/issues?state=open&type=issues&limit=100&sort=created&order=desc" \
  | python3 -c '
import sys,json
wip=set(int(x) for x in open("/tmp/fj_wip.txt").read().split())
for i in json.load(sys.stdin):
    labels=[l["name"] for l in i.get("labels") or []]
    if "🧊 parked" not in labels: continue
    print(i["number"],"|",i["title"],"|",",".join(labels),"|",i["created_at"],"|",(i.get("user") or {}).get("login","?"),"|","WIP" if i["number"] in wip else "")'
```

> Client-side filtering is used deliberately: `labels=🧊 parked` in the query string
> isn't URL-encoded by `tea api`, so the space+emoji breaks the request.

Show a compact table — number, title, labels, age (relative), author, and the
open-PR note. No preamble. If there are none, just say so.

---

If you hit a blocker (label filter param ignored, repo not resolvable), find a fix
and update this command for the future.
