# GoodWorkflows Workflow State Reference

`workflow-state.yaml` tracks lifecycle progress for Cursor-managed GoodWorkflows workflow work. It supplements `memory-bank/`; it does not replace source code, docs, or git history.

## Ownership

Only `goodworkflows-state-manager` writes `workflow-state.yaml`. Other skills request updates.

## Top-Level Schema

```yaml
schema_version: 1
project: GoodWorkflows
overall_status: idle | in_progress | blocked | completed
current_stage: "00-context"
active_cycle: null
stages:
  00-context:
    status: pending | in_progress | completed | blocked | skipped | waived
    started_at: null
    completed_at: null
    summary: ""
    artifacts: []
    verification: []
    blockers: []
evolve_cycles: []
decisions_log: []
issue_log: []
artifacts: []
verification_log: []
git_history:
  current_branch: null
  commits: []
  branches: []
agents: {}
```

## Stage Keys

- `00-context`
- `01-requirements`
- `02-verify-plan`
- `03-plan-tooling`
- `04-tech-plan`
- `05-verify-tech`
- `06-tech-tooling`
- `07-build`
- `08-verify-build`
- `09-qa`
- `10-e2e`
- `11-verify-impl`
- `12-verify-release`
- `13-real-run-smoke`
- `14-hotfix`
- `15-workflow-health`
- `16-evolve`
- `17-retrospective`

## Artifact Records

```yaml
- path: docs/workflows/new-workflow.md
  kind: docs | workflow | module | config | template | test | ci | memory | rule | skill | hook
  stage: "07-build"
  summary: "Added workflow documentation"
```

## Verification Records

```yaml
- stage: "08-verify-build"
  command: "nextflow run main.nf -profile test -stub-run --workflow ingest_export --input data/samplesheet.csv"
  status: passed | failed | skipped
  notes: "Stub-run validates wiring only"
```

## Evolve Cycle Records

```yaml
- id: EV-001
  title: "Add tcr_epitope workflow support"
  status: in_progress | completed | blocked
  feature_ids: ["F001"]
  current_stage: "04-tech-plan"
  affected_surfaces:
    - workflows
    - modules
    - docs
    - ci
  stages: {}
```

## Drift Checks

The state manager should flag likely drift when:

- `main.nf` workflow list changes without docs/schema/CI/template updates.
- `scripts/image-manifest.txt` changes without setup/cache parity updates.
- module process labels are not represented in relevant profile configs.
- `docs/` or `memory-bank/` describes fewer workflows than `main.nf`.
- stub-run verification is claimed for real container/GPU/SLURM behavior.
