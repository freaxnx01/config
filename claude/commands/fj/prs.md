---
description: List Forgejo pull requests awaiting review
---

Show open pull requests that need review in the current Forgejo repo.

## Forgejo access

Target the homelab Forgejo (`git.home.freaxnx01.ch`) via **`tea`** (login
`git-home`). Resolve `owner/name` from the remote for `tea api`:

```bash
url=$(git remote get-url origin); url=${url%.git}
repo=$(echo "$url" | sed -E 's#.*[:/]([^/]+/[^/]+)$#\1#')
me=$(tea api --login git-home user 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)["login"])')
```

## Approach

Forgejo has no GitHub `reviewDecision` / `review-requested:@me` search. Derive the
two buckets from the open PRs and their `requested_reviewers`:

```bash
tea api --login git-home "repos/$repo/pulls?state=open&limit=50&type=pulls" \
  | python3 -c "
import sys,json
me='$me'
prs=json.load(sys.stdin)
mine=[]; other=[]
for p in prs:
    if p.get('draft'): continue
    rr=[u.get('login') for u in (p.get('requested_reviewers') or [])]
    row=(p['number'], p['title'], (p.get('user') or {}).get('login','?'), p.get('created_at'))
    (mine if me in rr else other).append(row)
print('## My review requested')
for r in mine or [('—','none','','')]: print(*r, sep=' | ')
print('## Also awaiting review')
for r in other or [('—','none','','')]: print(*r, sep=' | ')
"
```

> If a PR has **no** requested reviewers and isn't authored by you, surface it under
> "also awaiting review" so nothing slips through. Forgejo also exposes per-PR
> review state via `repos/$repo/pulls/<n>/reviews` if you need approve/changes
> status — fetch it only when it matters, not for every PR in the list.

Compact table: number, title, author, age, bucket. Exclude drafts unless that's all
there is (agent/WIP PRs are often drafts). If none, say so.
