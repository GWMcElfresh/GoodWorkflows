---
name: 04-tech-plan
description: Create the technical implementation plan for a GoodWorkflows workflow/module change. Use after requirements are accepted.
---

# 04 Tech Plan

Read state, requirements, closest workflow/module patterns, and relevant domain skills.

## Plan

- Module boundaries and process names.
- Channel shapes, `take:`/`emit:` contracts, and file-mode tuple wrapping.
- Process labels, containers, and config resources.
- Template language and runtime concerns.
- Workflow registration in `main.nf`.
- Samplesheet generation and launcher updates.
- Tests, stub-run commands, docs, schema, README, and memory-bank updates.
- CI matrix or smoke wrapper impact.

## Subagents

Use specialist subagents for independent DSL2, template runtime, parity, verification, or docs planning when the change spans multiple surfaces.

## Output

Return an implementation plan with dependencies and verification commands. Update state with planned artifacts and decisions.
