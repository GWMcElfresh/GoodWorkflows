# GoodWorkflows CI failure → local repro

Use with `debug-github-actions-pr`. Workflow sources: `.github/workflows/`.

## Workflows and jobs

| Workflow file | Job / check pattern | What CI runs | Local repro |
|---------------|---------------------|--------------|-------------|
| `ci.yml` | **Lint and validate** | ShellCheck on HPC/CI scripts; workflow launcher parity; `nextflow config` (test, local); integration DSL2 stub-run | `shellcheck -S warning` glob in `goodworkflows-verify`; `bash scripts/ci/check_workflow_parity.sh`; `nextflow config -profile test`; integration stub from `ci.yml` |
| `ci.yml` | **Workflow smoke tests** + `(workflow_name)` | `scripts/ci/run_nextflow_smoke_tests.sh workflow <name>`; integration uses `--scmodal_use_cpu true` | `bash scripts/ci/run_nextflow_smoke_tests.sh workflow <name>`; for `integration`: add `--scmodal_use_cpu true` |
| `ci.yml` | **Module smoke tests** + `(module_name)` | `scripts/ci/run_nextflow_smoke_tests.sh module <name>` | `bash scripts/ci/run_nextflow_smoke_tests.sh module <name>` |
| `ci.yml` | **Optional container smoke** | Manual dispatch only; image pull + docker smoke | `bash scripts/ci/cache_container_images.sh` (local Podman/Docker if available) |
| `docs.yml` | **Build and validate docs site** | `generate_api_docs.sh`, `generate_example_plots.py`, `mkdocs build --strict` | `bash scripts/docs/generate_api_docs.sh && uvx --with matplotlib python scripts/docs/generate_example_plots.py && mkdocs build --strict` |
| `test-mcp.yml` | **Python 3.10 \| MCP Tests** / **3.11** | `npm ci` + build in `mcp-server/`; pytest unit/integration/e2e with `continue-on-error`; **Check test results** fails job | `cd mcp-server && npm ci && npm run build`; `python -m pytest tests/unit/ -v --tb=short`; then integration, e2e as needed |
| `docker-publish.yml` | **build-base** / **build-and-test** | Shared dockerDependencies workflows; runtime smoke in deps image | Only when `Dockerfile` or publish workflow changed; see `memory-bank/ci-cd.md` |

## Matrix cells (CI)

**Workflow smoke** (`ci.yml`): `ingest_export`, `ingest_tabulate`, `integration`, `nmf_vae`, `batch_effect_assessments`.

**Module smoke** (`ci.yml`): `ingest_labkey`, `ingest_file`, `ingest_metadata`, `ingest_url`, `export_counts`, `gene_harmonize`, `scmodal_integrate`, `tabulate`.

## Common failure signatures

| Log signal | Likely surface | Notes |
|------------|----------------|-------|
| `SC####` / `ShellCheck found issues` | shell | Files listed in `ci.yml` ShellCheck step |
| `Missing file:` | shell / CI | Path in `::error::` |
| `Workflow launcher parity` | launcher / CI | `bash scripts/ci/check_workflow_parity.sh` |
| `invalid workflow scopes` / `onError:` | DSL2 | Integration stub-run in lint job |
| `ERROR ~` / `Script_` / channel mismatch | DSL2 / config | Match matrix workflow or module name |
| `mkdocs build --strict` / broken link | docs | Regenerate API docs first; link only under `docs/` |
| `403 rate limit exceeded` + `language-server/releases/latest` | docs / nf-docs | Authenticated prefetch in `docs.yml`; local: `GITHUB_TOKEN=… bash scripts/docs/ensure_language_server.sh` |
| `Unit tests failed` / `Integration tests failed` / `E2E tests failed` | MCP / tests | Read pytest output in same job; check `test-results/*-output.txt` artifacts |
| `::error::Unit tests failed with outcome` | MCP | Aggregation step; scroll to failing pytest step |

## Artifacts

Failed smoke jobs upload:

- `workflow-<name>-artifacts` → `test-results/workflow/<name>/`
- `module-<name>-artifacts` → `test-results/module/<name>/`
- MCP: `test-results-py<version>`, `nextflow-logs-py<version>`

```bash
gh run download <run-id> -n workflow-integration-artifacts
```

## Branch not related to this PR

If failures match `main` and the branch is behind base:

```bash
git fetch origin main && git merge origin/main
```

Re-run `gh pr checks` after merge before editing application code.
