---
name: 12-verify-release
description: Verify GoodWorkflows release or PR readiness. Use after implementation sign-off and before handoff, PR creation, or optional real-run smoke checks.
---

# 12 Verify Release

This replaces Vecinita's deployment-readiness gate with GoodWorkflows release readiness.

## Checklist

- Focused verification and QA results are recorded.
- Docs, schema, README, and memory-bank are current.
- CI matrix or smoke wrapper impact is accounted for.
- Generated outputs are not staged as source.
- Risks distinguish stub-run, real container, GPU, LabKey, and SLURM coverage.
- PR or handoff summary can explain workflow impact concisely.

## Output

Update state with release readiness status and any required follow-up before PR/handoff.
