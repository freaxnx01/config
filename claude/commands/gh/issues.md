---
description: List open issues that are not WIP (no open PR), newest first
---

List open issues in the current repo that are **not work-in-progress** — i.e. have no **open** PR — **newest first**. Issues whose only linked PR is already merged still count as not-WIP and are shown.

`gh issue list` can't see PR links, so query the timeline via GraphQL and drop any issue that has an open linked PR (a `Closes #`/cross-reference or a development-linked PR still in flight):

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
    | map(select([.timelineItems.nodes[] | (.source // .subject) | .state] | map(select(. == "OPEN")) | length == 0))
    | .[] | {number, title, labels: [.labels.nodes[].name], age: .createdAt, author: .author.login}'
```

Show a compact table — number, title, labels, age (relative), author. No preamble.
If there are none, just say so.
