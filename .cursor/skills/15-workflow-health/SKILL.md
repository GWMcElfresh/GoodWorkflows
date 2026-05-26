---
name: 15-workflow-health
description: Review GoodWorkflows workflow health, drift, verification coverage, docs freshness, and local/cluster parity.
---

# 15 Workflow Health

Use this for audits, status checks, or before larger evolve work.

## Inspect

- `main.nf` workflow list vs docs, schema, CI, templates, and memory-bank.
- Process labels vs profile configs.
- Container image manifest vs setup/cache scripts.
- Stub-run coverage for modules and saved workflows.
- Known issues in `memory-bank/todos.md` and session notes.
- Generated docs/API freshness if relevant.

## Output

Return findings ordered by severity with recommended next actions. Update `workflow-state.yaml` issue log when the review is part of a tracked lifecycle.
