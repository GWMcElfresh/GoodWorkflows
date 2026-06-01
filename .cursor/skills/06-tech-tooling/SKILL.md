---
name: 06-tech-tooling
description: Prepare GoodWorkflows technical tooling before implementation. Use for CI smoke wrappers, launcher registry updates, image manifests, docs tooling, or test scaffolds needed by a workflow change.
---

# 06 Tech Tooling

Use this stage when implementation requires support files beyond modules/workflows.

**For new saved workflows, this stage is required** before `07-build` unless the user explicitly waives launcher/CI scope (record waiver in state).

## Prepare

- Module wrapper under `tests/modules/` when adding a module.
- Workflow smoke path via `scripts/ci/run_nextflow_smoke_tests.sh`.
- Workflow registry entries in `template/gw/check_workflows.sh` (use repo-root `test-data/` paths; verify resolution from `template/gw` cwd).
- Samplesheet generation in `template/gw/fetch_example_data.sh` **or** committed fixtures under `test-data/<workflow>/` plus generator script (e.g. `scripts/ci/create_*_smoke_rds.R`).
- `template/gw/run.sh` `VALID_WORKFLOWS` and help text synced with `main.nf`.
- Container entries in `scripts/image-manifest.txt`, `template/gw/setup.sh`, and CI cache scripts.
- Planned `.github/workflows/ci.yml` matrix row when workflow-level smoke exists.
- Docs generation expectations for `scripts/docs/generate_api_docs.sh` and `mkdocs build --strict`.
- Base image changes in `Dockerfile` and `.github/workflows/docker-publish.yml` when evolve work needs new shared runtimes or libraries (Python via `uv`, R, Rust).

## Required outputs (new workflows)

Before advancing to `07-build`, confirm or ticket each item:

| Item | Path / command |
| --- | --- |
| Launcher whitelist | `template/gw/run.sh` |
| Check registry | `template/gw/check_workflows.sh` `register` line + path audit |
| Fixtures | `test-data/<workflow>/` and/or `fetch_example_data.sh` section |
| CI smoke case | `scripts/ci/run_nextflow_smoke_tests.sh` |
| CI matrix | `.github/workflows/ci.yml` `workflow_smoke_tests` (when smoke exists) |
| Parity script | `bash scripts/ci/check_workflow_parity.sh` (after `07-build` lands list changes) |
| Cluster docs | `template/cluster/run.sh` comment + `docs/usage.md` |

Store the table in state (`artifacts` or evolve cycle summary) for `11-verify-impl` diffing.

## Base Image Tooling

When implementation needs dependencies beyond existing module containers, prefer the published base image for spikes:

| Need | Tool | Typical command |
| --- | --- | --- |
| Python packages | `uv` | `uv pip install --system <pkg>` or `uv venv` + `uv pip install` |
| R packages / projects | `remotes::install_github` or `install.packages` | Pre-install in `Dockerfile`; GitHub-only deps install into writable temp dir at runtime. See `16-evolve` guidance. |
| Reproducible R env | `Dockerfile` pre-install | All CRAN packages installed in `Dockerfile` build; no on-the-fly package manager needed. |

Promote spikes to module container or `Dockerfile` updates only when the dependency is required for production Nextflow processes or broadly shared across evolve cycles. See `16-evolve` for the full ad-hoc vs escalate guidance.

## Output

Record tooling surfaces in state with `status: completed`. If tooling is not needed, mark `skipped` with rationale—**not allowed** for new saved workflows that ship a CLI value unless user waived launchers.
