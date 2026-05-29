# GoodWorkflows Cursor Skills

Project skills for working on GoodWorkflows, a DSL2 Nextflow workflow manager for reusable single-cell analysis pipelines targeting local Podman and SLURM + Apptainer environments.

## How to Invoke

Skills are not shell commands. In **Agent** chat, Cursor loads them when your request matches their description, or when you name them explicitly.

**Automatic routing** — describe the task clearly:

- “Add a new saved workflow …” → `pipeline`, `16-evolve`, or `goodworkflows-workflow-manager`
- “Review this `.nf` for DSL2” → `goodworkflows-dsl2-validation`
- “Fix template / `.command.sh` error” → `goodworkflows-template-runtime`
- “Sync gw and cluster launchers” → `goodworkflows-template-parity`
- “What should I verify before a PR?” → `goodworkflows-verify`

**Explicit invocation** — name the skill in your message (most reliable):

```text
Use pipeline. Add a workflow called my_new_workflow.
```

```text
Follow 04-tech-plan and goodworkflows-dsl2-validation for this module.
```

```text
Use 08-verify-build on the ingest_export changes.
```

For long runbook detail, ask the agent to read the matching `reference.md` beside the skill (for example `goodworkflows-dsl2-validation/reference.md`).

**Subagents** — ask the parent agent to delegate; definitions live in `.cursor/agents/`:

```text
Use goodworkflows-state-manager for workflow-state.yaml only.
Delegate DSL2 to dsl2-specialist and launcher parity to template-parity-specialist.
```

**What runs without asking**

- `.cursor/rules/*.mdc` — persistent guidance (always-on or file-scoped).
- `.cursor/hooks.json` — advisory checks on edits and shell commands.
- `memory-bank/*.md` — durable project facts; mention them when planning (“read memory-bank/workflows.md”).

Reload Cursor after large `.cursor/` changes if skills or hooks do not seem to apply.

## New Workflow Entrypoint

Use this single prompt template for every new saved workflow or pipeline addition. The parent agent should read `workflow-state.yaml` through `goodworkflows-state-manager`, open or resume a `16-evolve` cycle, and then run the numbered skills in order. It must run **`grill-me`** before planning implementation details and record Q&A in `requirements-grill/`.

```text
Use pipeline.
Start a tracked evolve cycle for a new GoodWorkflows saved workflow/pipeline.

Workflow:
- CLI value:
- Scientific goal:
- Scope:
- Inputs and samplesheet expectations:
- Tools, modules, templates, or containers to use:
- Compute target:
- Required outputs:
- Known constraints:
- Verification target:

Use grill-me: create requirements-grill/{cycle}-{cli}.md from requirements-grill/_TEMPLATE.md,
grill me on missing requirements (samplesheet columns, params, outputs, docs/schema,
compute, acceptance criteria), and record answers in that file before planning.
Then delegate subagents by surface and proceed through the numbered skills.
```

The run should play out the same way each time:

1. `pipeline` reads state through `goodworkflows-state-manager` and records the evolve cycle.
2. `00-context` gathers closest workflow, module, config, launcher, docs, schema, and memory-bank patterns.
3. `grill-me` + `01-requirements` create/update `requirements-grill/{cycle}-{cli}.md` and grill until the contract is accepted.
4. `02-verify-plan` checks that contract, including samplesheet drift risk and launcher surfaces.
5. `04-tech-plan` plans DSL2, templates, launchers, docs, CI, tests, and verification, using specialist subagents when surfaces can be split.
6. `06-tech-tooling` is **required** before `07-build` for new workflows (fixtures, `run.sh`, CI smoke plan).
7. `05-verify-tech` through `13-real-run-smoke` proceed only as far as the accepted scope requires, with state updates at each stage boundary.

For samplesheets, every new workflow must maintain a drift ledger from requirements through release: required and optional columns, mode-specific constraints, parser/validator surfaces, generator surfaces, example samplesheets, docs/schema, launchers, tests, CI smoke inputs, and `memory-bank/` references must agree. Any column rename, default, optionality change, or mode constraint change is drift until those surfaces are updated or the gap is recorded.

**Launcher-ready** is separate from DSL2-ready: `template/gw/run.sh`, `check_workflows.sh`, fixtures, and `bash scripts/ci/check_workflow_parity.sh` must align with `main.nf` before handoff. See `pipeline` Completion Contract.

## Lifecycle Routing

Use `pipeline` for tracked multi-step work. It coordinates the numbered lifecycle, `workflow-state.yaml`, subagents, rules, hooks, and verification gates.

Use `grill-me` during `01-requirements` to capture questions and answers in `requirements-grill/` before technical planning.

| Goal | Route |
| --- | --- |
| Add a new saved workflow | `pipeline` -> `16-evolve` -> `00-context` through `13-real-run-smoke` as needed |
| Add a module to an existing workflow | `04-tech-plan` -> `07-build` -> `08-verify-build` |
| Fix a failing Nextflow run | `14-hotfix` with `goodworkflows-dsl2-validation` or `goodworkflows-template-runtime` |
| Audit workflow/docs/CI drift | `15-workflow-health` |
| Improve the Cursor workflow itself | `17-retrospective` |
| Run final checks before handoff | `08-verify-build`, `09-qa`, `10-e2e`, then `12-verify-release` |

## Numbered Stages

| Stage | Skill | Purpose |
| --- | --- | --- |
| 00 | `00-context` | Gather repo/workflow/module/config/docs context |
| 01 | `01-requirements` | Define workflow contract, params, outputs, profiles |
| 02 | `02-verify-plan` | Verify requirements before technical planning |
| 03 | `03-plan-tooling` | Install or audit Cursor lifecycle tooling |
| 04 | `04-tech-plan` | Plan modules, channels, templates, configs, tests, docs |
| 05 | `05-verify-tech` | Verify technical plan consistency |
| 06 | `06-tech-tooling` | Prepare smoke wrappers, launchers, CI, image lists |
| 07 | `07-build` | Implement planned changes |
| 08 | `08-verify-build` | Run focused verification |
| 09 | `09-qa` | Run broader quality checks |
| 10 | `10-e2e` | Run workflow-level smoke/e2e checks |
| 11 | `11-verify-impl` | Verify against requirements |
| 12 | `12-verify-release` | Verify PR/release readiness |
| 13 | `13-real-run-smoke` | Optional real Podman/GPU/SLURM smoke checks |
| 14 | `14-hotfix` | Debug and fix failures |
| 15 | `15-workflow-health` | Audit health and drift |
| 16 | `16-evolve` | Track feature/workflow evolution cycles; base image ad-hoc deps via `uv` / `uvr` |
| 17 | `17-retrospective` | Improve the workflow system |

## Domain Skills

| Skill | Use |
| --- | --- |
| `grill-me` | Structured requirements Q&A in `requirements-grill/` before `02-verify-plan` |
| `goodworkflows-repo-context` | Understand architecture and workflow intent |
| `goodworkflows-workflow-manager` | Compact route for stagewise workflow work |
| `goodworkflows-dsl2-validation` | Validate `.nf` and `.config` edits |
| `goodworkflows-template-runtime` | Edit R/Python/Shell templates safely |
| `goodworkflows-template-parity` | Keep local/cluster/CI launch surfaces aligned |
| `goodworkflows-verify` | Choose and report verification checks |

## Subagent Roles

- `goodworkflows-state-manager`: sole writer of `workflow-state.yaml`.
- `dsl2-specialist`: workflows, modules, configs, channel contracts, stubs.
- `template-runtime-specialist`: rendered templates and container runtime pitfalls.
- `template-parity-specialist`: launch templates, image lists, workflow registries, CI cache.
- `verify-runner`: exact command execution and coverage reporting.
- `docs-memory-updater`: docs, schema, README, and `memory-bank/` parity.

## Reference Notes

Long-form runbook material lives beside the active Cursor skills as `reference.md` files. Use those references for detailed workflow catalogs, DSL2 pitfalls, template runtime debugging, parity checks, and verification checklists.
