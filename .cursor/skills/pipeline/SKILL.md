---
name: pipeline
description: Orchestrate the full GoodWorkflows Cursor workflow lifecycle. Use when adding a new saved workflow, evolving multiple workflow features, bootstrapping a planned implementation, coordinating subagents, or resuming a numbered stage from workflow-state.yaml.
---

# GoodWorkflows Pipeline

This is the top-level lifecycle skill for GoodWorkflows. It adapts the Vecinita numbered workflow to a Nextflow workflow manager: every stage must preserve DSL2 correctness, template runtime safety, local/cluster parity, docs accuracy, and honest verification.

## Mandatory First Step

Before doing work, invoke or consult `goodworkflows-state-manager` with `operation: read_context` for this skill and the user's intent. Do not edit `workflow-state.yaml` directly unless you are the state manager.

## Stage Map

| Stage | Skill | GoodWorkflows purpose |
| --- | --- | --- |
| 00 | `00-context` | Gather repo, domain, workflow, module, config, docs, and memory-bank context. |
| 01 | `01-requirements` | Define workflow purpose, samplesheet columns, params, outputs, compute profile, and acceptance criteria. |
| 02 | `02-verify-plan` | Check requirements against existing workflows, DSL2 constraints, data contracts, and docs obligations. |
| 03 | `03-plan-tooling` | Ensure Cursor skills, rules, hooks, and state tracking support the requested workflow work. |
| 04 | `04-tech-plan` | Plan module boundaries, channel shapes, containers, labels, configs, tests, docs, and CI touch points. |
| 05 | `05-verify-tech` | Verify technical plan consistency before implementation. |
| 06 | `06-tech-tooling` | Prepare smoke wrappers, CI matrix entries, launchers, image lists, and docs tooling plans. |
| 07 | `07-build` | Implement modules, workflows, templates, configs, launchers, tests, docs, and memory-bank updates. |
| 08 | `08-verify-build` | Run focused build verification and fix failures before broader QA. |
| 09 | `09-qa` | Run repository-quality checks: shell, docs, Python/MCP, and parity review. |
| 10 | `10-e2e` | Run workflow-level smoke/e2e checks such as `check_workflows.sh` or CI smoke wrappers. |
| 11 | `11-verify-impl` | Confirm implementation satisfies requirements and accepted outputs. |
| 12 | `12-verify-release` | Confirm release/PR readiness, docs, CI expectations, and known risks. |
| 13 | `13-real-run-smoke` | Optional real Podman/GPU/SLURM smoke checks; never confuse with stub-run validation. |
| 14 | `14-hotfix` | Fix bugs from `nextflow.log`, generated `.command.sh`, CI failures, or runtime reports. |
| 15 | `15-workflow-health` | Inspect existing workflow health, drift, docs freshness, and verification coverage. |
| 16 | `16-evolve` | Add or refactor saved workflows and related features in a tracked evolve cycle. |
| 17 | `17-retrospective` | Improve skills, rules, hooks, docs, and workflow-state based on lessons learned. |

## Routing Rules

- New workflow or substantial refactor: run 00 -> 13 unless the user explicitly narrows scope.
- Small module/config/template task: use the nearest stage plus domain skills (`goodworkflows-dsl2-validation`, `goodworkflows-template-runtime`, `goodworkflows-template-parity`).
- Bug report or failing run: start at 14, then backfill docs/tests if the fix changes behavior.
- Health check or drift review: start at 15.
- Skill/rule/hook improvement: start at 17, then update state and routing docs.

## Subagent Strategy

Use subagents when work naturally separates:

- State manager: read/update `workflow-state.yaml`; no code implementation.
- DSL2 specialist: workflows, modules, configs, channel shapes.
- Template runtime specialist: R/Python/Shell templates and Groovy rendering.
- Template parity specialist: `template/gw`, `template/cluster`, image manifests, CI cache.
- Verify runner: executes checks and reports exact coverage.
- Docs/memory updater: docs, schema, README, and `memory-bank/`.

The parent agent remains responsible for user communication, final decisions, and integrating results.

## Completion Contract

At each stage boundary, update state through the state manager with artifacts, verification results, open decisions, and next stage. At final handoff, report what changed, what was verified, what was not verified, and any remaining risk.
