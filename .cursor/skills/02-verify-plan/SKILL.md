---
name: 02-verify-plan
description: Verify GoodWorkflows requirements before technical planning. Use after 01-requirements or when reviewing a proposed workflow addition for missing data contracts, docs, or validation scope.
---

# 02 Verify Plan

Read state and the requirements brief.

## Checks

- Workflow name follows `snake_case` for files and CLI values.
- Samplesheet columns are sufficient for ingest mode and downstream modules.
- Samplesheet drift ledger covers parser/validator surfaces, generator surfaces, example samplesheets, docs/schema, launchers, tests, CI smoke inputs, and `memory-bank/` references.
- **Launcher surfaces checklist** is filled (see `requirements-grill/_TEMPLATE.md`); not only DSL2/docs boxes.
- **06-tech-tooling scope** is listed (fixtures, `run.sh`, `check_workflows.sh`, CI matrix, images)—not deferred to “later.”
- **Verification target** names the trio: repo stub-run, `check_workflows.sh --workflow <cli>`, `run_nextflow_smoke_tests.sh workflow <cli>`.
- **Fixture strategy** is explicit: committed `test-data/`, `fetch_example_data.sh`, and/or `scripts/ci/create_*` generator.
- **Samplesheet path convention** documented (repo-root `test-data/` vs `template/gw/` generated sheets).
- Outputs can be stubbed and documented.
- Compute profile is explicit and compatible with CI stub-run.
- Requirements identify all docs/schema/memory-bank touch points.
- No user-facing promise depends on unverified real GPU/container/SLURM behavior.

## Result

Return pass/fail with blockers. If passed, update state and recommend `04-tech-plan` or `03-plan-tooling` if Cursor lifecycle assets are missing.
