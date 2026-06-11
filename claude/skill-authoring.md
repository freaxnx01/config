# Skill authoring

When you create or edit an agent skill (a `SKILL.md`), make it **self-improving**:
end the skill body with an instruction telling the skill to fix and document its own
blockers, e.g.

> If you run into blockers, find a solution and update this skill for the future.

This turns each skill into a living document that accumulates hard-won fixes, so the
next run doesn't re-derive them. Apply it to every new skill by default — whether
written by hand or via a skill-creator — unless the user says otherwise.

Pair it with a **stop hook** that asks Claude to run the skill's verification step if
it hasn't already, so the loop closes on its own: run → hit blocker → solve → write the
fix back into `SKILL.md`.

Two more authoring rules worth keeping:

- **Don't be too prescriptive** — give intent and guardrails, not rigid step-by-step
  that breaks on edge cases.
- **Mention the tools** you want the skill to use (MCP servers, commands, etc.).
