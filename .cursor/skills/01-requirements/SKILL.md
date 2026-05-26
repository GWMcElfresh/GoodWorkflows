---
name: 01-requirements
description: Define requirements for a GoodWorkflows workflow/module change. Use before adding a saved workflow, changing samplesheets, outputs, params, or compute profile expectations.
---

# 01 Requirements

Read `pipeline-preamble.md` and state context first.

## Capture

- Workflow name and CLI value for `--workflow`.
- Scientific purpose and stage sequence.
- Input samplesheet name, required columns, optional columns, and mode-specific constraints.
- Required params, defaults, and schema/doc impact.
- Outputs, published paths, and data format expectations.
- Compute target: CPU, local GPU, SLURM GPU, or optional real-run profile.
- Acceptance criteria and minimum stub-run scope.

## GoodWorkflows Constraints

- Every new process needs a stub output matching real outputs.
- New containers belong in the image manifest and setup/cache lists.
- Docs and memory-bank updates are requirements, not optional follow-up.

## Output

Produce a concise requirements brief and update state artifacts/decisions. If requirements are underspecified, ask before planning technical details.
