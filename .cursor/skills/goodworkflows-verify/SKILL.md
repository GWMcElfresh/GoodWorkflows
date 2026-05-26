---
name: goodworkflows-verify
description: Verify GoodWorkflows changes before handoff, PR, or commit. Use after edits to Nextflow workflows/modules/configs, templates, shell scripts, docs, CI, samplesheets, or workflow-manager scaffolds.
---

# GoodWorkflows Verify

Choose checks based on files touched. Prefer fast local checks first, then workflow-level smoke tests.

## Check Matrix

- `.nf`: Nextflow parser/stub-run for affected workflow or module wrapper.
- `.config`: profile load or a representative `-profile test -stub-run`.
- `modules/local/**/templates/*.py`: Python syntax where render-safe, plus affected module/workflow stub-run.
- `modules/local/**/templates/*.r` or `.R`: R syntax where available, plus affected module/workflow stub-run.
- `.sh`: ShellCheck if installed; otherwise run `bash -n`.
- `template/gw/**` or `template/cluster/**`: run script syntax checks and parity review.
- `docs/**`, `mkdocs.yml`, `scripts/docs/**`: `mkdocs build --strict` or the documented docs generation path when dependencies are available.
- `mcp-server/**`: use its npm build/test commands from `mcp-server/package.json`.

## Standard Commands

```bash
nextflow run main.nf -profile test -stub-run --workflow ingest_export --input data/samplesheet.csv
bash -n template/gw/run.sh
bash -n template/gw/check_workflows.sh
mkdocs build --strict
```

Adjust samplesheets and workflow names to the affected area. Do not claim real container, GPU, or SLURM validation unless it actually ran.

## Review Before Handoff

- Confirm no generated outputs were edited intentionally unless they are docs/site artifacts the user requested.
- Confirm docs and memory-bank notes match behavior changes.
- Confirm container image and workflow lists remain in sync.
- Summarize verification honestly, including missing local tools.
