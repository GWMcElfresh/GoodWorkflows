# Workflows

## Overview

Three saved workflows, selected via `--workflow <name>`:

| Workflow | CLI name | Modules | Compute |
|---|---|---|---|
| Integration Pipeline | `integration` | INGEST → EXPORT_COUNTS → GENE_HARMONIZE → SCMODAL_INTEGRATE | HPC + GPU |
| Ingest + Export | `ingest_export` | INGEST → EXPORT_COUNTS | CPU (local or HPC) |
| Ingest + Tabulate | `ingest_tabulate` | INGEST_METADATA → TABULATE | CPU (local or HPC) |

---

## 1. Integration Pipeline (`integration`)

**File:** `workflows/integration_pipeline.nf`

### Purpose
Full cross-species scRNA-seq integration: download Seurat objects from LabKey, export 10x-like count matrices, harmonize genes across species via ortholog mapping, and train scMODAL to produce a shared latent embedding with Leiden clustering.

### Input
- Samplesheet CSV with columns: `sample_id`, `output_file_id`, `species`
- LabKey credentials via `.netrc`

### Stages

| Stage | Process | Input | Output |
|---|---|---|---|
| 1 | INGEST | `meta` map per sample | `{id}.rds`, `{id}_metadata.csv` |
| 2 | EXPORT_COUNTS | `(meta, rds)` tuple | `{id}_counts/` (matrix.mtx, features.tsv, barcodes.tsv, obs_meta.csv) |
| 3 | GENE_HARMONIZE | Collected list of count dirs | `harmonized_outputs/` (per-species .h5ad, manifest, ortholog mapping) |
| 4 | SCMODAL_INTEGRATE | `harmonized_outputs/` directory | `model_outputs/` (ckpt.pth, latent_clustered.h5ad, training_history.csv) |

### Compute Requirements
- **GPU required** (NVIDIA, via `--gres=gpu:1 --qos=gpu`)
- **SLURM executor required** (blocked on local executor)
- **CI exception:** `--scmodal_use_cpu true` + `GITHUB_ACTIONS` env bypasses GPU guard (stub only)

### Key Parameters
- `--species_order` — comma-separated species order (default: `human,macaque,mouse`)
- `--export_assay` — Seurat assay to export (default: `RNA`)
- `--scmodal_latent` — latent dimensions (default: 20)
- `--scmodal_training_steps` — training steps (default: 10000)
- `--scmodal_batch_size` — batch size (default: 500)
- `--scmodal_neighbors` — KNN neighbors (default: 30)
- `--leiden_resolution` — Leiden clustering resolution (default: 0.5)

### Outputs
```
outputs/
├── ingest/                   # Flattened: {sample_id}.rds, {sample_id}_metadata.csv
├── counts/                   # Flattened: {sample_id}_counts/ directories
├── harmonized/               # Per-species harmonized AnnData files
└── scmodal/                  # Model checkpoint, latent embedding, clusters
```

> **Note:** As of Nextflow 26.04.0, `publishDir` cannot use `${meta.id}` interpolation, so outputs are published flat (e.g., `outputs/ingest/SAMPLE_01.rds`) rather than nested in per-sample subdirectories.

---

## 2. Ingest + Export (`ingest_export`)

**File:** `workflows/ingest_export.nf`

### Purpose
Download Seurat objects from LabKey and export them as 10x-like count directories. No harmonization or integration. Suitable for local/Mac testing.

### Input
- Samplesheet CSV with columns: `sample_id`, `output_file_id`, `species`
- LabKey credentials via `.netrc`

### Stages

| Stage | Process | Input | Output |
|---|---|---|---|
| 1 | INGEST | `meta` map per sample | `{id}.rds`, `{id}_metadata.csv` |
| 2 | EXPORT_COUNTS | `(meta, rds)` tuple | `{id}_counts/` |

### Compute Requirements
- CPU only
- Runs on local executor or SLURM

### Outputs
```
outputs/
├── ingest/                   # Flattened: {sample_id}.rds, {sample_id}_metadata.csv
└── counts/                   # Flattened: {sample_id}_counts/ directories
```

> **Note:** As of Nextflow 26.04.0, `publishDir` cannot use `${meta.id}` interpolation, so outputs are published flat (e.g., `outputs/ingest/SAMPLE_01.rds`) rather than nested in per-sample subdirectories.

---

## 3. Ingest + Tabulate (`ingest_tabulate`)

**File:** `workflows/ingest_tabulate.nf`

### Purpose
Download cell-level metadata from LabKey (without downloading full Seurat objects) and aggregate into a wide subject-level summary table (`subjectIdTable.csv`). Suitable for cohort QC.

### Input
- Samplesheet CSV with columns: `sample_id`, `output_file_id`, `species`
- LabKey credentials via `.netrc`

### Stages

| Stage | Process | Input | Output |
|---|---|---|---|
| 1 | INGEST_METADATA | `meta` map per sample | `{id}_metadata.csv` |
| 2 | TABULATE | Collected CSVs + tabulation params | `subjectIdTable.csv` |

### Key Parameters
- `--tabulate_id_cols` — CSV of ID columns (default: `cDNA_ID,SubjectId,Vaccine,Timepoint,Tissue`)
- `--tabulate_celltype_cols` — extra cell-type columns beyond standard RIRA columns
- `--tabulate_parent_col` — parent lineage column for hierarchy filtering
- `--tabulate_celltype_parent_map` — `celltype_col:parentValue` pairs

### Tabulation Logic
- Standard RIRA columns always processed: `RIRA_Immune.cellclass`, `RIRA_TNK_v2.cellclass`, `RIRA_Myeloid_v3.cellclass`
- Parent-child hierarchy: child columns computed only over rows matching parent value
- Deduplicates barcodes across cohort files
- Produces `Fraction_<level>`, `Count_<level>`, `Total_<col>_Cells` columns

### Compute Requirements
- CPU only
- Runs on local executor or SLURM

### Outputs
```
outputs/
├── ingest/                   # Flattened: {sample_id}_metadata.csv
└── tabulate/                 # subjectIdTable.csv
```

> **Note:** As of Nextflow 26.04.0, `publishDir` cannot use `${meta.id}` interpolation, so outputs are published flat (e.g., `outputs/ingest/SAMPLE_01_metadata.csv`) rather than nested in per-sample subdirectories.
