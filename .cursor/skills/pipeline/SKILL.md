---
name: pipeline
description: Orchestrate the full GoodWorkflows Cursor workflow lifecycle. Use when adding a new saved workflow, evolving multiple workflow features, bootstrapping a planned implementation, coordinating subagents, or resuming a numbered stage from workflow-state.yaml.
---

# GoodWorkflows Pipeline

This is the top-level lifecycle skill for GoodWorkflows. It adapts the Vecinita numbered workflow to a Nextflow workflow manager: every stage must preserve DSL2 correctness, template runtime safety, local/cluster parity, docs accuracy, and honest verification.

## Mandatory First Step

Before doing work, invoke or consult `goodworkflows-state-manager` with `operation: read_context` for this skill and the user's intent. Do not edit `workflow-state.yaml` directly unless you are the state manager.

For new workflows, run `grill-me` during stage 01: create or update the cycle grill file under `requirements-grill/` and do not advance to `02-verify-plan` until that file is **accepted**.

## Stage Map

| Stage | Skill | GoodWorkflows purpose |
| --- | --- | --- |
| 00 | `00-context` | Gather repo, domain, workflow, module, config, docs, and memory-bank context. |
| 01 | `01-requirements` + `grill-me` | Define workflow contract; record Q&A in `requirements-grill/{cycle}-{cli}.md` before planning. |
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
| 15 | `15-workflow-health` | Review existing workflow health, drift, docs freshness, and verification coverage. |
| 16 | `16-evolve` | Add or refactor saved workflows and related features in a tracked evolve cycle. |
| 17 | `17-retrospective` | Improve skills, rules, hooks, docs, and workflow-state based on lessons learned. |

## New-workflow stage ordering (mandatory)

For every new `--workflow` CLI value, use this order unless the user explicitly narrows scope (e.g. “DSL2 only, no templating”):

```text
00 → 01 → 02 → 04 → 05 → 06 → 07 → 08 → 09 → 10 → 11 → 12
```

**Invalid progressions** (state manager should block or record drift):

| Invalid | Required fix |
| --- | --- |
| `07-build` started while `06-tech-tooling` is `pending` | Complete or skip 06 with documented rationale |
| `07-build` marked completed without launcher surfaces | Finish parity checklist or log `issue_log` |
| Evolve cycle closed without `10-e2e` for the new CLI | Run workflow-specific e2e; record in `verification_log` |
| Grill launcher checklist `[x]` but files missing | Record drift; do not mark `11-verify-impl` passed |

**Do not skip `06-tech-tooling`** for new saved workflows. Skipping requires user-approved scope that excludes launchers, recorded in state.

## Launcher-ready vs DSL2-ready

A saved workflow is **DSL2-ready** when `main.nf`, modules, configs, stubs, and docs compile.

A saved workflow is **launcher-ready** when users can run it without ad-hoc path fixes:

| Surface | Local (`template/gw`) | Cluster (`template/cluster`) |
| --- | --- | --- |
| Workflow whitelist | `run.sh` `VALID_WORKFLOWS` | `run.sh` comment + `docs/usage.md` |
| Smoke registry | `check_workflows.sh` (paths resolve from `template/gw` cwd) | N/A |
| Fixtures | `fetch_example_data.sh` and/or committed `test-data/<workflow>/` | User samplesheet documented |
| Images | `setup.sh` + `scripts/image-manifest.txt` | Same URI in manifest for pre-pull |
| CI | `run_nextflow_smoke_tests.sh` case; matrix row when smoke exists | Same |

**Handoff-ready** requires **launcher-ready** plus verification trio (see Completion Contract).

## Routing Rules

- New workflow or substantial refactor: run 00 -> 12 unless the user explicitly narrows scope.
- Small module/config/template task: use the nearest stage plus domain skills (`goodworkflows-dsl2-validation`, `goodworkflows-template-runtime`, `goodworkflows-template-parity`).
- Bug report or failing run: start at 14, then backfill docs/tests if the fix changes behavior.
- Health check or drift review: start at 15.
- Skill/rule/hook improvement: start at 17, then update state and routing docs.

## Subagent Strategy

Use subagents when work naturally separates:

| When | Subagent | Deliverable |
| --- | --- | --- |
| End of `04-tech-plan` | template-parity specialist | File-level launcher & CI plan |
| End of `07-build` (before `08`) | template-parity specialist | Diff vs launcher checklist |
| `08` / `10` | verify-runner | Verification trio commands + logs |
| Ongoing | State manager | `workflow-state.yaml` only |
| DSL2 | dsl2-specialist | workflows, modules, configs |
| Templates | template-runtime-specialist | R/Python/Shell templates |
| Docs | docs-memory-updater | docs, schema, memory-bank |

The parent agent remains responsible for user communication, final decisions, and integrating results.

## Completion Contract

At each stage boundary, update state through the state manager with artifacts, verification results, open decisions, and next stage.

### Verification trio (new or changed workflows)

Record all applicable commands in `verification_log`:

```bash
# 1. DSL2 wiring
nextflow run main.nf -profile test -stub-run \
  --workflow <cli> --input <samplesheet>

# 2. Local launcher registry (from template/gw)
bash check_workflows.sh --workflow <cli>

# 3. CI-equivalent smoke
bash scripts/ci/run_nextflow_smoke_tests.sh workflow <cli>
```

Precondition: fixture files and samplesheets exist (committed or generated). If missing, record **blocked** in verification—not silent skip.

### Automated parity (before `12-verify-release`)

```bash
bash scripts/ci/check_workflow_parity.sh
```

Fails when `main.nf` `supportedWorkflows` diverges from `template/gw/run.sh` or schema enum. CI matrix gaps warn unless `--strict-ci`.

### Effortless-run acceptance (`11-verify-impl`)

| Target | Minimum evidence |
| --- | --- |
| Local | `setup.sh` images; `fetch_example_data.sh` or `test-data/`; `run.sh --workflow <cli>` accepts CLI |
| Cluster | `docs/usage.md`; `WORKFLOW` documented; images in manifest |
| Requirements | Grill launcher checklist maps to file paths or commands |

At final handoff, report what changed, what was verified, what was not verified, and any remaining risk.
