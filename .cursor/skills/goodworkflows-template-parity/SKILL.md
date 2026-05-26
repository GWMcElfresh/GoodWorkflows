---
name: goodworkflows-template-parity
description: Maintain parity between GoodWorkflows local and cluster workflow-manager scaffolds. Use when editing template/gw, template/cluster, run scripts, setup scripts, image manifests, workflow lists, fetch_example_data, or CI container caching.
---

# GoodWorkflows Template Parity

Use this when changing launcher scaffolds, workflow lists, or container image lists.

## Source of Truth

- Workflow list: `main.nf` `supportedWorkflows`.
- Container image list: `scripts/image-manifest.txt`.
- Local launcher scaffold: `template/gw/`.
- Cluster launcher scaffold: `template/cluster/` when present.

## Keep in Sync

- Container images in `scripts/image-manifest.txt`, `template/gw/setup.sh`, and `scripts/ci/cache_container_images.sh`.
- Valid workflow lists in `main.nf`, `template/gw/run.sh`, `template/gw/check_workflows.sh`, and cluster docs/comments.
- Samplesheet generation in `template/gw/fetch_example_data.sh` for workflows that need non-default inputs.
- Docs and workflow tables in `README.md`, `docs/workflows/*.md`, `docs/index.md`, `docs/parameters.md`, and `mkdocs.yml`.
- Stub output validation in CI scripts when adding new workflows or changing output names.

## Intentional Divergences

Do not "fix" these unless the user asks:

- Local uses Podman/local GPU conventions; cluster uses SLURM + Apptainer SIF cache.
- Cluster scripts may require LabKey credentials and SBATCH metadata; local scripts should not.
- Cluster logs may disable ANSI output; local logs can be more interactive.
- Nextflow binary discovery can differ between local and cluster.

## Adding a Workflow

Checklist:

- Add the workflow implementation under `workflows/`.
- Add it to `main.nf` and the schema enum where applicable.
- Add or confirm module labels and profile resources.
- Add templates and stubs for all new processes.
- Add samplesheet generation and `check_workflows.sh` registry entries if the default samplesheet is insufficient.
- Update user-facing docs and memory-bank notes.
- Run the relevant `-profile test -stub-run` path.
