# Parameters

Complete reference for all `--param` flags accepted by `main.nf`. Defaults are set in [`configs/base.config`](https://github.com/GWMcElfresh/GoodWorkflows/blob/main/configs/base.config). The machine-readable version of this reference is [`nextflow_schema.json`](https://github.com/GWMcElfresh/GoodWorkflows/blob/main/nextflow_schema.json).

---

## Input / output options

| Parameter | Default | Description |
|---|---|---|
| `--workflow` | `full` | Named workflow to execute. One of `full`, `ingest_export`, `ingest_tabulate`. |
| `--input` | `data/samplesheet.csv` | Path to the samplesheet CSV. See [Data Formats → Samplesheet](data-formats.md#samplesheet). |
| `--outdir` | `outputs/` | Directory where published results are written. |

---

## LabKey / Prime-seq options

These are **required** for all three workflows.

| Parameter | Default | Description |
|---|---|---|
| `--labkey_base_url` | _(required)_ | Base URL of the LabKey server (e.g. `https://labkey.example.org`). |
| `--labkey_folder` | _(required)_ | LabKey folder path (e.g. `/My/Project/Folder`). |

---

## Species options

| Parameter | Default | Description |
|---|---|---|
| `--species_order` | `human,macaque,mouse` | Comma-separated list of species. Controls the ordering during harmonization and scMODAL integration. Each value must match the `species` column in the samplesheet. |
| `--export_assay` | `RNA` | Seurat assay name to export as count matrix in EXPORT_COUNTS. |

---

## Tabulation options

These parameters affect only `--workflow ingest_tabulate`.

| Parameter | Default | Description |
|---|---|---|
| `--tabulate_id_cols` | `cDNA_ID,SubjectId,Vaccine,Timepoint,Tissue` | Comma-separated subject-level identity columns to carry into `subjectIdTable.csv`. `cDNA_ID` is always included as the primary sample key. |
| `--tabulate_celltype_cols` | _(empty)_ | Extra cell-type annotation columns to tabulate beyond the standard RIRA set. Leave empty to use only the standard RIRA columns auto-detected in the metadata. |
| `--tabulate_parent_col` | _(empty)_ | Parent lineage column used to gate child cell-type columns. Defaults to `RIRA_Immune.cellclass` when empty. |
| `--tabulate_celltype_parent_map` | _(empty)_ | Comma-separated `celltype_col:parentValue` pairs to extend or override the built-in hierarchy. Example: `RIRA_TNK_v2.cellclass:TNK,RIRA_Myeloid_v3.cellclass:Myeloid`. |

---

## scMODAL integration options

These parameters affect only `--workflow full`.

| Parameter | Default | Description |
|---|---|---|
| `--scmodal_container` | `ghcr.io/gwmcelfresh/scmodal-cuda:latest` | Container image for `GENE_HARMONIZE` and `SCMODAL_INTEGRATE`. Must include `scmodal`, `torch`, `scanpy`, and `anndata`. |
| `--scmodal_latent` | `20` | Number of latent dimensions in the scMODAL VAE embedding. |
| `--scmodal_training_steps` | `10000` | Number of VAE training steps. Increase for larger datasets. |
| `--scmodal_batch_size` | `500` | Mini-batch size during scMODAL training. |
| `--scmodal_neighbors` | `30` | Number of nearest neighbours for the KNN graph built on the latent embedding. |
| `--leiden_resolution` | `0.5` | Leiden clustering resolution. Higher values produce more clusters. |

---

## CI / testing options

!!! warning "Not for production use"
    `--scmodal_use_cpu` is intended exclusively for GitHub Actions smoke tests.
    Using it outside CI will produce stub outputs with no scientific validity and will print a warning.

| Parameter | Default | Description |
|---|---|---|
| `--scmodal_use_cpu` | `false` | Bypasses the local-executor GPU guard for `--workflow full` and runs `SCMODAL_INTEGRATE` as a stub (requires `-stub-run`). Emits a warning if `GITHUB_ACTIONS` env is not set. |

---

## Generic options

| Parameter | Default | Description |
|---|---|---|
| `--help` | `false` | Print help text and exit. |
