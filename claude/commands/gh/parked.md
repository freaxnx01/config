---
description: List parked issues (🧊 parked) — intentionally deferred, newest first
---

List open issues in the current repo that are **parked** — i.e. carry the `🧊 parked` label (understood but intentionally deferred) — **newest first**. These are the issues excluded from `/gh:issues`.

Query via GraphQL so the open/merged state of any linked PR can be shown alongside each parked issue:

```bash
gh api graphql \
  -f owner="$(gh repo view --json owner -q .owner.login)" \
  -f name="$(gh repo view --json name -q .name)" \
  -f query='
query($owner:String!,$name:String!){
  repository(owner:$owner,name:$name){
    issues(states:OPEN, first:100, orderBy:{field:CREATED_AT, direction:DESC}){
      nodes{
        number title createdAt
        author{login}
        labels(first:20){nodes{name}}
        timelineItems(itemTypes:[CROSS_REFERENCED_EVENT,CONNECTED_EVENT], first:50){
          nodes{
            ... on CrossReferencedEvent{source{... on PullRequest{state}}}
            ... on ConnectedEvent{subject{... on PullRequest{state}}}
          }
        }
      }
    }
  }
}' \
  --jq '.data.repository.issues.nodes
    | map(select([.labels.nodes[].name] | index("🧊 parked")))
    | .[] | {number, title, labels: [.labels.nodes[].name], age: .createdAt, author: .author.login}'
```

Show a compact table — number, title, labels, age (relative), author. No preamble.
If there are none, just say so.
