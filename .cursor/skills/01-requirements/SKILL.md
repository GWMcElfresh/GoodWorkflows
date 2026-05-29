---
name: 01-requirements
description: Define requirements for a GoodWorkflows workflow/module change. Use before adding a saved workflow, changing samplesheets, outputs, params, or compute profile expectations.
---

# 01 Requirements

Read `pipeline-preamble.md` and state context first.

## Grill file (required for new workflows)

Use `grill-me` before treating requirements as complete.

- Create or update `requirements-grill/{CYCLE_ID}-{CLI_VALUE}.md` from `requirements-grill/_TEMPLATE.md`.
- Record every decision in that file's **Answer** blocks; do not rely on chat history alone.
- Block `02-verify-plan` until grill `Status` is `accepted` and blocking questions are answered.
- Register the grill file path in `workflow-state.yaml` via `goodworkflows-state-manager`.

## Capture

- Workflow name and CLI value for `--workflow`.
- Scientific purpose and stage sequence.
- Input samplesheet name, required columns, optional columns, and mode-specific constraints.
- Samplesheet drift ledger: parser/validator surfaces, generator surfaces, example samplesheets, docs/schema, launchers, tests, CI smoke inputs, and `memory-bank/` references that must agree.
- **Launcher surfaces checklist** (separate from DSL2 drift): `run.sh`, `check_workflows.sh`, `fetch_example_data.sh`, `setup.sh`/manifest, cluster comments, CI matrix—see grill template.
- **Fixture strategy** and **samplesheet path convention** (repo-root `test-data/` vs `template/gw/`).
- Required params, defaults, and schema/doc impact.
- Outputs, published paths, and data format expectations.
- Compute target: CPU, local GPU, SLURM GPU, or optional real-run profile.
- Acceptance criteria and minimum stub-run scope.

## GoodWorkflows Constraints

- Every new process needs a stub output matching real outputs.
- New containers belong in the image manifest and setup/cache lists.
- Docs and memory-bank updates are requirements, not optional follow-up.

## Output

Produce a concise requirements brief (derived from the accepted grill file) and update state artifacts/decisions. Treat samplesheet column renames, defaults, optionality, and mode constraints as drift until every affected surface is identified. If requirements are underspecified, use `grill-me` and update the grill file before planning technical details.
