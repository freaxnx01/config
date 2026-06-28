---
description: Open Forgejo issues ordered bugs/fixes first, then quick wins
---

Fetch open issues (with body + labels) from the current Forgejo repo, then present
them ordered for triage.

## Forgejo access

Target the homelab Forgejo (`git.home.freaxnx01.ch`) via **`tea`** (login
`git-home`):

```bash
url=$(git remote get-url origin); url=${url%.git}
repo=$(echo "$url" | sed -E 's#.*[:/]([^/]+/[^/]+)$#\1#')
tea api --login git-home "repos/$repo/issues?state=open&type=issues&limit=100&sort=created&order=desc" \
  | python3 -c 'import sys,json;[print(i["number"],"||",i["title"],"||",",".join(l["name"] for l in i.get("labels") or []),"||",(i.get("body") or "")[:200].replace(chr(10)," ")) for i in json.load(sys.stdin)]'
```

## Ordering

Present them ordered for triage:

1. **Bugs / fixes first** — issues whose labels or title/body signal a defect
   (labels like `bug`, `type:bug`, `defect`, `regression`, `fix`; or clear bug
   wording).
2. **Then quick wins** — remaining low-complexity / small-scope issues (short,
   well-defined; labels like `good-first-issue`, `chore`, `docs`, `small`). Easiest
   first, by your judgment from title/body/labels.
3. **Everything else** after that.

For each: number, title, key labels, and a 3–6 word reason it's in that bucket. Be
concise — this is a reading aid, don't start any work.
