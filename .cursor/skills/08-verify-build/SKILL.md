---
name: 08-verify-build
description: Verify GoodWorkflows build changes with focused checks. Use after implementation and before QA, PR, or handoff.
---

# 08 Verify Build

Load `goodworkflows-verify` and choose the narrowest checks that cover changed files.

## Checks

- Module: `nextflow run tests/modules/<module>.nf -profile test -stub-run`.
- Workflow: verification **trio** below when a saved workflow changed.
- Config: `nextflow config -profile test` or representative stub-run.
- Shell: CI-parity `shellcheck -S warning` on the glob in `goodworkflows-verify` (not only `bash -n`).
- Docs: docs generation/build if docs surfaces changed.
- Parity: `bash scripts/ci/check_workflow_parity.sh` when `main.nf` or `template/gw/run.sh` changed.

## Workflow verification trio

When adding or changing a saved workflow, run and record:

```bash
nextflow run main.nf -profile test -stub-run \
  --workflow <cli> --input <samplesheet>

cd template/gw && bash check_workflows.sh --workflow <cli>

bash scripts/ci/run_nextflow_smoke_tests.sh workflow <cli>
```

**Blocked (not skip)** if fixtures or samplesheets are missing—generate them first (`scripts/ci/create_*`, `fetch_example_data.sh`, or commit `test-data/`).

## Output

Record exact commands and status in `workflow-state.yaml`. If checks cannot run, record why and what remains unverified.
