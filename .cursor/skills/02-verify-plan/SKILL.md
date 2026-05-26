---
name: 02-verify-plan
description: Verify GoodWorkflows requirements before technical planning. Use after 01-requirements or when reviewing a proposed workflow addition for missing data contracts, docs, or validation scope.
---

# 02 Verify Plan

Read state and the requirements brief.

## Checks

- Workflow name follows `snake_case` for files and CLI values.
- Samplesheet columns are sufficient for ingest mode and downstream modules.
- Outputs can be stubbed and documented.
- Compute profile is explicit and compatible with CI stub-run.
- Requirements identify all docs/schema/memory-bank touch points.
- No user-facing promise depends on unverified real GPU/container/SLURM behavior.

## Result

Return pass/fail with blockers. If passed, update state and recommend `04-tech-plan` or `03-plan-tooling` if Cursor lifecycle assets are missing.
