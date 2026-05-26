---
name: 13-real-run-smoke
description: Run optional real GoodWorkflows smoke checks with Podman, GPU, LabKey, or SLURM/Apptainer. Use only when the user asks for real runtime validation beyond stub-run.
---

# 13 Real Run Smoke

Real runtime checks can be expensive, environment-specific, or data-dependent. Confirm scope before running them.

## Scope Options

- Local Podman real workflow via `template/gw/run.sh`.
- Local GPU workflow with `local_gpu` profile.
- SLURM/Apptainer launch via cluster template or root launcher.
- LabKey ingest path with credentials available through approved mechanisms.

## Rules

- Do not run destructive cleanup without explicit approval.
- Do not confuse real-run validation with CI stub-run.
- Capture logs and first root cause if a run fails.

## Output

Record command, environment, result, logs location, and limitations in state.
