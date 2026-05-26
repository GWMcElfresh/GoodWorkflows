---
name: 16-evolve
description: Manage GoodWorkflows evolve cycles for adding or refactoring saved workflows, modules, templates, docs, CI, or launcher behavior.
---

# 16 Evolve

Use this when the user asks to add a workflow, add several workflow features, or substantially refactor a workflow surface.

## Cycle Setup

- Create or resume an evolve cycle in `workflow-state.yaml`.
- Capture feature IDs, affected surfaces, intended stage path, and verification target.
- Prefer one evolve cycle for related workflow/module/docs/CI changes.

## Delta Mode

Numbered stages 00-13 can run in delta mode for an active evolve cycle. Only redo the stage details affected by the requested change.

## GoodWorkflows Evolve Defaults

- Add workflow lists and docs together.
- Add samplesheet generation with workflow implementation.
- Add stub-run coverage before real-run expectations.
- Replace unshipped branch behavior directly; do not preserve compatibility with current-branch mistakes.

## Output

Update cycle status, current stage, touched surfaces, and next step.
