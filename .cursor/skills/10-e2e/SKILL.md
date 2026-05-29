---
name: 10-e2e
description: Run workflow-level GoodWorkflows smoke or end-to-end checks. Use after build verification for serial workflow checks, CI smoke wrappers, or optional local real runs.
---

# 10 E2E

This stage validates workflow behavior at the largest practical scope.

## Stub/E2E Options

- **Required for new workflows:** `template/gw/check_workflows.sh --workflow <cli>` (not only full serial run).
- `template/gw/check_workflows.sh` for serial local scaffold checks.
- `scripts/ci/run_nextflow_smoke_tests.sh workflow <cli>` for CI-equivalent checks.
- `nextflow run main.nf -profile test -stub-run --workflow <name> --input <samplesheet>` for targeted wiring.

## Path rules

- Samplesheets under repo-root `test-data/` must resolve via `PIPELINE_ROOT` in `check_workflows.sh` (not `template/gw/test-data/...`).
- Registry `register` lines using `--input test-data/...` are valid when the file exists at `${PIPELINE_ROOT}/test-data/...`.

## Parity

Run before closing an evolve cycle:

```bash
bash scripts/ci/check_workflow_parity.sh
```

Use `--strict-ci` when CI matrix must include every `main.nf` workflow.

## Real Run Boundary

Real Podman/GPU/SLURM checks belong in `13-real-run-smoke` unless explicitly requested here. Do not present real-run failures as stub-run failures or vice versa.

## Output

Record scope, commands, results, artifacts, and limitations.
