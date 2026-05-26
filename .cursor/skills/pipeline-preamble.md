# GoodWorkflows Pipeline Preamble

All numbered skills and pipeline orchestrators follow these rules.

## State First

For multi-step workflow work, read state through `goodworkflows-state-manager` before acting. The state manager is the sole writer of `workflow-state.yaml`; other skills request updates but do not edit the file directly.

## Repo Invariants

- Source-of-truth workflow list: `main.nf` `supportedWorkflows`.
- Source-of-truth container list: `scripts/image-manifest.txt`.
- Keep `docs/`, `README.md`, `nextflow_schema.json`, CI, launch templates, and `memory-bank/` aligned with behavior changes.
- Do not edit generated run artifacts: `work/`, `outputs/`, `logs/`, `runs/`, `.nextflow/`, `.ci/docker-cache/`, `site/`, or generated binary test data.
- Preserve local/cluster intent: local scripts target Podman/local GPU; cluster scripts target SLURM + Apptainer.

## Verification Honesty

Stub-run validates DSL2 wiring and process stubs. It does not validate real containers, GPU memory, LabKey access, or SLURM behavior. Real Podman/GPU/SLURM checks must be described separately.

## Change Discipline

- Prefer existing module/workflow patterns over new abstractions.
- Keep module responsibilities narrow.
- Preserve sparse/raw matrices through export, harmonize, and merge stages unless a model stage owns normalization.
- Use profile configs and process labels for resources; avoid environment-specific behavior inside templates.
- For unshipped branch work, replace incorrect behavior directly rather than layering compatibility shims.

## Subagent Protocol

Subagents return evidence and recommendations. The parent agent integrates changes, manages user questions, and coordinates state updates. Do not let subagents edit `workflow-state.yaml` unless they are the state manager.

## Handoff Template

```markdown
## Handoff

Stage: <stage>
Changed surfaces: <paths/categories>
Verification run: <commands/results>
Not verified: <missing tools/data/environments>
State updated: <yes/no and key>
Next step: <one action>
```
