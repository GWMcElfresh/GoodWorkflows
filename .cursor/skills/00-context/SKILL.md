---
name: 00-context
description: Gather GoodWorkflows context before planning a workflow change. Use at the start of a new workflow addition, major refactor, health review, or evolve cycle.
---

# 00 Context

Read `pipeline-preamble.md` and request `read_context` from `goodworkflows-state-manager`.

## Gather

- Repo overview: `README.md`, `memory-bank/architecture.md`, `memory-bank/workflows.md`.
- Conventions: `memory-bank/conventions.md`, `memory-bank/nextflow_syntax.md`.
- Closest workflow: `workflows/*.nf` and matching `docs/workflows/*.md`.
- Closest modules: `modules/local/**/main.nf` and templates.
- Runtime profiles: `configs/base.config` and relevant profile configs.
- Detailed source notes: `reference.md` files beside the relevant `.cursor/skills/*/SKILL.md`.

## Output

Return a context brief with:

- workflow or feature intent
- nearest existing pattern
- touched surfaces
- known DSL2/template/parity risks
- recommended next stage

Update state with context artifacts and drift risks.
