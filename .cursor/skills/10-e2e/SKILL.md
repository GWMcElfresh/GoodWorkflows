---
name: 10-e2e
description: Run workflow-level GoodWorkflows smoke or end-to-end checks. Use after build verification for serial workflow checks, CI smoke wrappers, or optional local real runs.
---

# 10 E2E

This stage validates workflow behavior at the largest practical scope.

## Stub/E2E Options

- `template/gw/check_workflows.sh` for serial local scaffold checks.
- `scripts/ci/run_nextflow_smoke_tests.sh` for CI-equivalent workflow/module checks.
- `nextflow run main.nf -profile test -stub-run --workflow <name> --input <samplesheet>` for targeted workflow wiring.

## Real Run Boundary

Real Podman/GPU/SLURM checks belong in `13-real-run-smoke` unless explicitly requested here. Do not present real-run failures as stub-run failures or vice versa.

## Output

Record scope, commands, results, artifacts, and limitations.
