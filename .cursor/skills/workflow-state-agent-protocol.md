# Workflow State Agent Protocol

Pipeline skills communicate with `goodworkflows-state-manager` through concise operation prompts.

## Operations

### `read_context`

Use before starting a numbered stage or resuming a lifecycle task.

```yaml
operation: read_context
skill_id: "04-tech-plan"
user_intent: "add workflow for ..."
mode: greenfield | evolve | hotfix | health | retrospective
```

The state manager returns:

- current stage status
- prerequisites and blockers
- likely touched surfaces
- recommended next step
- drift risks from `memory-bank/`, docs, CI, workflow lists, and image manifests

### `update`

Use after a stage changes progress, artifacts, verification, decisions, blockers, or git metadata.

```yaml
operation: update
skill_id: "08-verify-build"
update_payload:
  current_stage: "09-qa"
  stages:
    08-verify-build:
      status: completed
      summary: "Affected workflow stub-run passed"
      verification:
        - command: "nextflow run main.nf -profile test -stub-run --workflow example --input data/samplesheet.csv"
          status: passed
```

### `init_project`

Use only when `workflow-state.yaml` is missing or malformed and the user approved lifecycle tracking.

## Rules

- The state manager writes state atomically.
- Append `decisions_log`, `issue_log`, `verification_log`, and `git_history.commits`; do not silently delete history.
- State is bookkeeping, not proof. Verification records must name exact commands or explain skipped checks.
- If state and code disagree, code and docs are evidence; state should record the drift rather than hide it.

## Blocking Deviations

Return `blocking: true` when:

- a requested stage depends on incomplete prerequisite stages and the user has not waived them.
- an evolve request has no active or newly initialized evolve cycle.
- the task would edit generated artifacts as source.
- the requested handoff claims verification that did not run.
- scope has drifted outside the active cycle or user request.
