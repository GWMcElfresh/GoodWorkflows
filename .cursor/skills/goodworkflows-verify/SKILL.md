---
name: goodworkflows-verify
description: Verify GoodWorkflows changes before handoff, PR, or commit. Use after edits to Nextflow workflows/modules/configs, templates, shell scripts, docs, CI, samplesheets, or workflow-manager scaffolds.
---

# GoodWorkflows Verify

Choose checks based on files touched. Prefer fast local checks first, then workflow-level smoke tests.

## Host-aware entrypoint (first local check)

```bash
bash scripts/test/run_host_tests.sh --affected
```

See skill `18-host-test` for WSL (light), Mac (CPU real), and Bazzite (GPU real) routing. Profiles: `template/gw/test-hosts.yaml`.

## Check Matrix

- `.nf`: Nextflow parser/stub-run for affected workflow or module wrapper.
- `.config`: profile load or a representative `-profile test -stub-run`.
- `modules/local/**/templates/*.py`: Python syntax where render-safe, plus affected module/workflow stub-run.
- `modules/local/**/templates/*.r` or `.R`: R syntax where available, plus affected module/workflow stub-run.
- `.sh`: ShellCheck if installed; otherwise run `bash -n`.
- `template/gw/**` or `template/cluster/**`: run script syntax checks and parity review.
- **Any** edited `.sh` under the CI ShellCheck glob (see below): run the **CI-parity** command before handoff — do not rely on `bash -n` alone.
- `docs/**`, `mkdocs.yml`, `scripts/docs/**`: run `bash scripts/docs/generate_api_docs.sh` then `mkdocs build --strict` (matches `.github/workflows/docs.yml`). Link only to paths under `docs/`; repo files like `template/gw/test-hosts.yaml` use backticks, not markdown links. API workflow anchors live in `docs/api/generated/workflows.md` after generation.
- `mcp-server/**`: use its npm build/test commands from `mcp-server/package.json`.

## Standard Commands

```bash
nextflow run main.nf -profile test -stub-run --workflow ingest_export --input data/samplesheet.csv
bash -n template/gw/run.sh
bash -n template/gw/check_workflows.sh
mkdocs build --strict
```

Adjust samplesheets and workflow names to the affected area. Do not claim real container, GPU, or SLURM validation unless it actually ran.

## CI-parity ShellCheck (required for shell edits)

GitHub Actions runs `shellcheck -S warning` on the same file set as `.github/workflows/ci.yml` (“ShellCheck HPC and CI helpers”). Run this from repo root after changing any listed script (including `template/gw/check_workflows.sh`):

```bash
shellcheck -S warning \
  slurm_nextflow.sh \
  slurm_sync_repo.sh \
  template/gw/run.sh \
  template/gw/setup.sh \
  template/gw/fetch_example_data.sh \
  template/gw/check_workflows.sh \
  template/cluster/run.sh \
  scripts/*.sh \
  scripts/ci/*.sh
```

Common failures to fix (do not silence without reason):

- **SC2034**: variable assigned but never read — remove it, use it, or `export` if a sourced library or child process needs it.
- **SC2206**: word splitting in arrays — use an explicit disable only when intentional (see existing `check_workflows.sh` patterns).

`scripts/test/run_host_tests.sh` runs ShellCheck on affected paths but may use default severity; for PRs touching CI-listed scripts, always run the command above locally when `shellcheck` is installed.

## Review Before Handoff

- Confirm no generated outputs were edited intentionally unless they are docs/site artifacts the user requested.
- Confirm docs and memory-bank notes match behavior changes.
- Confirm container image and workflow lists remain in sync.
- Summarize verification honestly, including missing local tools.
