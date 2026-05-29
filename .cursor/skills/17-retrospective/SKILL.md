---
name: 17-retrospective
description: Improve the GoodWorkflows Cursor workflow system after a build, hotfix, health review, or repeated failure. Use to update skills, rules, hooks, state schema, docs, and memory-bank lessons.
---

# 17 Retrospective

Use this when the process itself needs improvement.

## Review

- What caused delay, confusion, or repeated tool failures?
- Did a workflow ship in `main.nf` without launcher/CI parity? If yes, update `pipeline`, grill template, or `scripts/ci/check_workflow_parity.sh`.
- Which DSL2/template/parity rules should become persistent guidance?
- Were hooks too noisy or too weak?
- Did state accurately reflect work and verification?
- Did docs or memory-bank drift from code?

## Update Targets

- `.cursor/skills/`
- `.cursor/rules/`
- `.cursor/hooks/`
- `.cursor/agents/`
- `workflow-state.yaml`
- `memory-bank/session-notes.md` and `memory-bank/todos.md`

## Output

Record process changes and update routing docs if future agents should behave differently.
