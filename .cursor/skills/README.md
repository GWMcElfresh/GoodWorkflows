# GoodWorkflows Cursor Skills

Project skills for working on GoodWorkflows, a DSL2 Nextflow workflow manager for reusable single-cell analysis pipelines targeting local Podman and SLURM + Apptainer environments.

## Lifecycle Routing

Use `pipeline` for tracked multi-step work. It coordinates the numbered lifecycle, `workflow-state.yaml`, subagents, rules, hooks, and verification gates.

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
| 16 | `16-evolve` | Track feature/workflow evolution cycles |
| 17 | `17-retrospective` | Improve the workflow system |

## Domain Skills

| Skill | Use |
| --- | --- |
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
