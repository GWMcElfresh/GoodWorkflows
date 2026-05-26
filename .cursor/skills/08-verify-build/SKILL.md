---
name: 08-verify-build
description: Verify GoodWorkflows build changes with focused checks. Use after implementation and before QA, PR, or handoff.
---

# 08 Verify Build

Load `goodworkflows-verify` and choose the narrowest checks that cover changed files.

## Checks

- Module: `nextflow run tests/modules/<module>.nf -profile test -stub-run`.
- Workflow: `nextflow run main.nf -profile test -stub-run --workflow <name> --input <samplesheet>`.
- Config: `nextflow config -profile test` or representative stub-run.
- Shell: ShellCheck or `bash -n`.
- Docs: docs generation/build if docs surfaces changed.

## Output

Record exact commands and status in `workflow-state.yaml`. If checks cannot run, record why and what remains unverified.
