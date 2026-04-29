# CI/CD

## GitHub Actions Workflows

The repository uses GitHub Actions for three layers of validation:

### 1. Workflow Smoke Tests

**Script:** `scripts/ci/run_nextflow_smoke_tests.sh`

Runs `main.nf` with `-profile test -stub-run` for each saved workflow:

| Workflow | Command | Notes |
|---|---|---|
| `integration` | `nextflow run main.nf -profile test -stub-run --workflow integration --scmodal_use_cpu true ...` | GPU guard bypassed for CI |
| `ingest_export` | `nextflow run main.nf -profile test -stub-run --workflow ingest_export ...` | — |
| `ingest_tabulate` | `nextflow run main.nf -profile test -stub-run --workflow ingest_tabulate ...` | — |

**What it validates:**
- DSL2 wiring (all channels connect correctly)
- Process stub blocks execute
- Workflow completes without errors
- No containers or real computation needed

### 2. Module Smoke Tests

**Location:** `tests/modules/`

Each module has an independent test wrapper that exercises it in isolation:

| Test File | Module Tested |
|---|---|
| `tests/modules/scmodal_integrate.nf` | SCMODAL_INTEGRATE |

These run with `-profile test -stub-run` to validate each module's DSL2 interface independently.

### 3. Docs Validation and Deploy

**Trigger:** PRs and pushes that touch workflows, docs, schema, or docs tooling.

**Steps:**
1. Regenerate `nf-docs` API reference: `bash scripts/docs/generate_api_docs.sh`
2. Regenerate synthetic example plots: `uvx --with matplotlib python scripts/docs/generate_example_plots.py`
3. Build docs with strict mode: `mkdocs build --strict`

**Deploy:** On pushes to `main`, the site is deployed to GitHub Pages at `gwmcelfresh.github.io/GoodWorkflows/`.

## Container Caching for CI

**Script:** `scripts/ci/cache_container_images.sh`

Pre-pulls and caches module container images into `.ci/docker-cache/` during GitHub Actions runs. This enables container-dependent validation without re-pulling images on every run.

## Test Profile Details

`-profile test` (from `configs/test.config`):
- Disables all container engines (podman, docker, singularity, apptainer)
- Uses local executor
- Minimal resources: 1 CPU, 2 GB RAM, 30 min timeout
- `container = null` — processes run directly on the CI runner

## Synthetic Test Data

**Location:** `tests/fixtures/synthetic_trial_data/`

Seeded synthetic fixture bundle used for:
- Docs example plots (immune composition, subject table heatmap, count matrix heatmap)
- Vignette walkthrough
- Does not depend on sensitive or machine-local files

## CI Design Principles

1. **Stub-run for speed** — No real computation in CI; stub blocks validate wiring
2. **No containers in CI** — `-profile test` disables all container engines
3. **Independent module tests** — Each module tested in isolation
4. **Docs as code** — Docs regenerated and validated in CI, deployed automatically
5. **Synthetic data** — Docs examples use seeded fixtures, not real data