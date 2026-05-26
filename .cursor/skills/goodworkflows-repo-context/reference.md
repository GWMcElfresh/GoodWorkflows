# GoodWorkflows Repo Context Reference

Long-form context migrated from the retired root `skills/` directory.

## Current Workflow Catalog

| Workflow | CLI | Stages | Compute | Samplesheet |
| --- | --- | --- | --- | --- |
| Integration Pipeline | `integration` | INGEST -> EXPORT_COUNTS -> GENE_HARMONIZE -> SCMODAL_INTEGRATE | GPU/HPC | `samplesheet.csv` |
| Ingest + Export | `ingest_export` | INGEST -> EXPORT_COUNTS | CPU | `samplesheet.csv` |
| Ingest + Tabulate | `ingest_tabulate` | INGEST_METADATA -> TABULATE | CPU | `tabulate_samplesheet.csv` |
| NMF-VAE Factorize | `nmf_vae` | INGEST -> EXPORT_COUNTS -> NMF_VAE_MERGE_COUNTS -> NMF_VAE_FACTORIZE | GPU/CPU fallback | `nmf_vae_samplesheet.csv` |
| GEX MIL Pipeline | `gex_mil` | INGEST -> EXPORT_COUNTS -> GEX_MERGE_COUNTS -> TRAIN_GEX_MIL | GPU | `samplesheet.csv` with `SubjectId` |
| TCR MIL Pipeline | `tcr_mil` | INGEST -> QUANTIFY_TCR -> MERGE_TCR_METADATA -> TRAIN_TCR_MIL | GPU | `samplesheet.csv` |
| TCR Epitope | `tcr_epitope` | INGEST -> QUANTIFY_TCR -> MERGE_TCR_METADATA -> EMBED_CLONES -> PREDICT_BINDING -> TCR_UMAP -> JOIN_SEURAT | GPU | `tcr_epitope_samplesheet.csv` plus `--binding_model_path` |

## Ingest Modes

Each sample row uses exactly one of:

- `output_file_id`: LabKey download, requires `.netrc` mount for LabKey processes only.
- `url`: HTTP download.
- `path`: local Seurat `.rds` file, passed as `tuple val(meta), path(file)`.
- `metadata_path`: standalone metadata CSV for `ingest_tabulate`, passed as `tuple val(meta), path(metadata_file)`.

File-mode processes must receive wrapped tuples:

```groovy
INGEST_FILE(ch_local.file.map { meta -> [meta, file(meta.path)] }).rds
INGEST_METADATA_FILE(ch_metadata.file.map { meta -> [meta, file(meta.metadata_path)] }).metadata
```

## Preprocessing Ownership

Each module owns one responsibility:

- EXPORT modules write 10x-like outputs and do not normalize.
- HARMONIZE and MERGE modules keep raw counts sparse when possible.
- Model/training modules own normalization and may densify on GPU/high-memory nodes.

Rule of thumb:

- HARMONIZE, MERGE, EXPORT: do not normalize and do not densify unless the contract requires it.
- INTEGRATE, FACTORIZE, MIL: model code owns normalization.

## Container Families

- `ghcr.io/bimberlabinternal/cellmembrane:latest`: export counts.
- `ghcr.io/gwmcelfresh/scmodal:latest`: gene harmonize and scModal integration, including checkpoint/resume behavior.
- `ghcr.io/gwmcelfresh/nmf-vae:latest`: NMF-VAE merge/factorize.
- `ghcr.io/gwmcelfresh/mil-ton`: GEX/TCR MIL modules.

## Config and Runtime Notes

- Config inheritance starts at `nextflow.config`, then `configs/base.config`, then selected profiles.
- Keep params in `base.config`; use profiles for resources, executors, and container runtime.
- SLURM memory escalation should be inline inside closures, not top-level `def`.
- GPU processes may need retry handling for CUDA OOM, OS SIGKILL, and SLURM time-limit/preemption signals.
- Do not add bare `gpu = 1` unless the required Nextflow GPU plugin path is intentionally configured; GoodWorkflows uses labels/profile settings for GPU allocation.

## Doc Review Convention

After `.nf`, `.config`, template, launcher, schema, or output-format changes, check:

- `docs/data-formats.md`
- `docs/usage.md`
- `docs/parameters.md`
- `docs/workflows/*.md`
- `docs/index.md`
- `mkdocs.yml`
- `README.md`
- `memory-bank/*.md`
- `scripts/image-manifest.txt` when containers changed

## Generated and Local Data Policy

Do not commit generated run artifacts or local binary data:

- `work/`, `outputs/`, `logs/`, `runs/`, `.nextflow*`
- `template/gw/data/`, `template/gw/runs/`, generated samplesheets
- `.ci/docker-cache/`
- large `.rds` test data and generated TCR epitope model artifacts

## Local Dev Troubleshooting

If `which Rscript` resolves but execution fails with "No such file or directory", check for stale distrobox-exported symlinks into Podman overlay layers. Remove the stale symlink or run inside the active distrobox/container.
