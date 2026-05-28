---
name: 06-tech-tooling
description: Prepare GoodWorkflows technical tooling before implementation. Use for CI smoke wrappers, launcher registry updates, image manifests, docs tooling, or test scaffolds needed by a workflow change.
---

# 06 Tech Tooling

Use this stage when implementation requires support files beyond modules/workflows.

## Prepare

- Module wrapper under `tests/modules/` when adding a module.
- Workflow smoke path via `scripts/ci/run_nextflow_smoke_tests.sh`.
- Workflow registry entries in `template/gw/check_workflows.sh`.
- Samplesheet generation in `template/gw/fetch_example_data.sh`.
- Container entries in `scripts/image-manifest.txt`, `template/gw/setup.sh`, and CI cache scripts.
- Docs generation expectations for `scripts/docs/generate_api_docs.sh` and `mkdocs build --strict`.
- Base image changes in `Dockerfile` and `.github/workflows/docker-publish.yml` when evolve work needs new shared runtimes or libraries (Python via `uv`, R via `uvr`, Rust).

## Base Image Tooling

When implementation needs dependencies beyond existing module containers, prefer the published base image for spikes:

| Need | Tool | Typical command |
| --- | --- | --- |
| Python packages | `uv` | `uv pip install --system <pkg>` or `uv venv` + `uv pip install` |
| R packages / projects | `uvr` | `uvr init`, `uvr add <pkg>`, `uvr sync`, `uvr run script.R` |
| Reproducible R env in CI | `uvr` | `uvr sync --frozen` |

Promote spikes to module container or `Dockerfile` updates only when the dependency is required for production Nextflow processes or broadly shared across evolve cycles. See `16-evolve` for the full ad-hoc vs escalate guidance.

## Output

Record tooling surfaces in state. If tooling is not needed, mark this stage skipped with rationale.
