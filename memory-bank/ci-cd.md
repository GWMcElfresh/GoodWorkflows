# CI/CD

## GitHub Actions Workflows

The repository uses GitHub Actions for four layers of validation:

### 1. CI Workflow (`ci.yml`)

**Triggers:** Push/PR to `main`, `copilot/**` branches; manual dispatch.

**Jobs:**
- **lint_and_validate** — ShellCheck on HPC/CI scripts, Nextflow profile validation (test, local, slurm)
- **workflow_smoke_tests** — Runs each saved workflow with `-profile test -stub-run` (matrix: ingest_export, ingest_tabulate, integration)
- **module_smoke_tests** — Runs each module in isolation with `-profile test -stub-run` (matrix: ingest_labkey, ingest_file, ingest_url, ingest_metadata, export_counts, gene_harmonize, scmodal_integrate, tabulate)
- **container_smoke** — Optional, manual-only: primes cached module images and smoke-tests rdiscvr, cellmembrane, scmodal containers

**What it validates:**
- DSL2 wiring (all channels connect correctly)
- Process stub blocks execute
- Workflow completes without errors
- No containers or real computation needed (except optional container_smoke)

### 2. MCP Server Tests (`test-mcp.yml`)

**Triggers:** Push/PR to main/master on relevant paths (mcp-server, tests, workflows, modules, configs); manual dispatch.

**Matrix:** Python 3.10, 3.11

**Steps:**
1. Checkout → Setup Python (with pip cache) → Install Python deps
2. Setup Node.js 20 (with npm cache, keyed on `mcp-server/package-lock.json`) → `npm ci` → `npm run build`
3. Setup Java 17 → Install Nextflow
4. Run unit tests → integration tests → e2e tests (all with `continue-on-error: true`)
5. **Check test results** step — aggregates outcomes and fails the job if any test layer failed
6. Upload artifacts: test-results (JUnit XML), Nextflow logs, generated workflows

**Key design:** Tests use `continue-on-error: true` so all layers run, but a final check step fails the job if any layer failed.

### 3. Docs Validation and Deploy (`docs.yml`)

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