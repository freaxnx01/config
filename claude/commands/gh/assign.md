---
description: Assign an issue to a GitHub coding agent (@copilot / @claude) to implement it
argument-hint: "<issue-number> [copilot|claude] — agent defaults to copilot"
---

Hand an existing issue to a GitHub **coding agent** so it opens a PR implementing it.
`$ARGUMENTS` is `<issue-number>` plus an optional agent (`copilot` or `claude`).

## Agent default — prefer `@copilot`

If no agent is given, default to **copilot**. In practice the Copilot coding agent
(`copilot-swe-agent`) is the reliable trigger: it reacts within ~a minute and starts a
session. The Anthropic agent (`anthropic-code-agent`) is available too, but only pick it
when the user explicitly asks for Claude (or has confirmed it's responsive in this repo).

## Preconditions — confirm before assigning

1. The issue is **open**, **not parked** (`🧊 parked`), and not already assigned to an agent —
   `gh issue view <N> --json state,labels,assignees`. If parked or already agent-owned, stop and say so.
2. The issue is **actionable** — it has clear scope/AC. If it's `❓ to-be-defined` or
   `needs-enrichment`, warn that the agent will likely produce a weak PR, and confirm before proceeding.
3. The chosen agent is **assignable** in this repo (see the suggestedActors query below); if it
   isn't listed, the GitHub app isn't installed — say so and stop.

## Post TDD contract

Post a TDD requirement comment on the issue so the assigned agent reads it as part
of the issue context:

```bash
gh issue comment <N> --body "## TDD Required — Non-Negotiable

Implement using Test-Driven Development:
- **RED:** Write a failing test first. Run it. Confirm it fails for the right reason.
- **GREEN:** Write the minimal code to make it pass. No more.
- **REFACTOR:** Clean up while keeping tests green.

No production code without a failing test first.

Your PR description must include TDD evidence:
- RED: command run + relevant failing output
- GREEN: command run + passing output"
```

Replace `<N>` with the actual issue number (from `$ARGUMENTS`).

## Resolve the actor and assign

Bots can't be assigned via `gh issue edit --add-assignee` (it resolves logins as users).
Use the GraphQL `replaceActorsForAssignable` mutation with the bot's actor id:

```bash
n="<issue-number>"; agent="${1:-copilot}"
case "$agent" in
  copilot) bot="copilot-swe-agent" ;;
  claude)  bot="anthropic-code-agent" ;;
  *) echo "agent must be 'copilot' or 'claude'"; exit 1 ;;
esac
owner="$(gh repo view --json owner -q .owner.login)"
name="$(gh repo view --json name -q .name)"

# Issue node id
issueId="$(gh api graphql -f owner="$owner" -f name="$name" -F n="$n" -f query='
query($owner:String!,$name:String!,$n:Int!){
  repository(owner:$owner,name:$name){ issue(number:$n){ id } } }' \
  --jq '.data.repository.issue.id')"

# Bot actor id (also proves the agent is assignable here)
botId="$(gh api graphql -f owner="$owner" -f name="$name" -f query='
query($owner:String!,$name:String!){
  repository(owner:$owner,name:$name){
    suggestedActors(capabilities:[CAN_BE_ASSIGNED], first:50){
      nodes{ login __typename ... on Bot{ id } ... on User{ id } } } } }' \
  --jq ".data.repository.suggestedActors.nodes[] | select(.login==\"$bot\") | .id")"
[ -z "$botId" ] && { echo "Agent '$bot' is not assignable in this repo (app not installed)."; exit 1; }

# Assign (replaceActorsForAssignable handles bot actors; replaces existing assignees)
gh api graphql -f assignableId="$issueId" -f actorId="$botId" -f query='
mutation($assignableId:ID!,$actorId:ID!){
  replaceActorsForAssignable(input:{assignableId:$assignableId, actorIds:[$actorId]}){
    assignable{ ... on Issue{ number assignees(first:10){ nodes{ login } } } } } }' \
  --jq '.data.replaceActorsForAssignable.assignable | "assigned #\(.number) → \([.assignees.nodes[].login]|join(", "))"'
```

## After

Print the issue number, the agent assigned, and the issue URL. Note that the agent works
on its **own branch** and opens a (usually draft) PR — watch for the 👀 reaction as the
signal it picked the task up. Review its PR later with `/gh:review`. Don't merge anything.

If there's no `gh`/repo context, say so and stop.
