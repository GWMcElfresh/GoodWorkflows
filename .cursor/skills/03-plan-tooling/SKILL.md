---
name: 03-plan-tooling
description: Install or verify Cursor workflow tooling for GoodWorkflows. Use when creating or updating skills, rules, hooks, state files, subagent protocols, or lifecycle gates.
---

# 03 Plan Tooling

This stage manages Cursor infrastructure, not pipeline science code.

## Verify

- `.cursor/skills/pipeline/SKILL.md` exists.
- Numbered 00-17 skills exist.
- `workflow-state.yaml`, state reference, and agent protocol exist.
- `goodworkflows-state-manager` is the sole state writer.
- Rules cover planning, spec adherence, build execution, DSL2, templates, parity, and verification.
- Hooks are advisory unless the action is destructive.

## Output

Update state with installed tooling artifacts and any missing lifecycle pieces. Then move to `04-tech-plan` for workflow implementation work.
