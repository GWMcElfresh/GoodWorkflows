# Data Formats

This page documents every data format consumed and produced by GoodWorkflows, organized by pipeline stage.

---

## Samplesheet

**Path:** `--input` (default `data/samplesheet.csv`)

The samplesheet is the single entry point for all three workflows. It is a comma-separated file with a header row.

### Required columns

| Column | Type | Description |
|---|---|---|
| `sample_id` | string | Unique identifier for the sample. Used as the output directory name and filename prefix throughout the pipeline. |
| `output_file_id` | string | LabKey output file ID used by Rdiscvr to locate and download the Seurat RDS or metadata from the Prime-seq server. |
| `species` | string | Species label for this sample. Must match one of the values in `--species_order`. |

### Example

```csv
sample_id,output_file_id,species
SAMPLE_01,12345,human
SAMPLE_02,12346,macaque
SAMPLE_03,12347,mouse
```

!!! tip "Multi-sample runs"
    Add one row per sample. All samples in the samplesheet are processed in parallel (within executor limits).

---

## Stage outputs

### INGEST — Seurat RDS

**File:** `outputs/ingest/{sample_id}/{sample_id}.rds`  
**Produced by:** [`ingest_export`](workflows/ingest-export.md), [`full`](workflows/full-pipeline.md)

A Seurat v5 RDS object containing:

- Raw `RNA` assay counts (and potentially other assays present on LabKey)
- `meta.data` slot populated with all LabKey metadata columns available for the sample
- CellBarcode identifiers and quality-control metrics from Prime-seq

This file is the primary artifact of INGEST and the direct input to EXPORT_COUNTS.

---

### INGEST_METADATA — Cell metadata CSV

**File:** `outputs/ingest/{sample_id}/{sample_id}_metadata.csv`  
**Produced by:** [`ingest_tabulate`](workflows/ingest-tabulate.md)

A flat CSV of cell-level metadata downloaded without the RNA counts. Each row is one cell (droplet barcode).

| Column | Description |
|---|---|
| `barcode` | Cell barcode identifier (normalized from `cellbarcode` alias if needed) |
| `sample_id` | Sample identifier (injected during ingest) |
| `species` | Species label from the samplesheet |
| `output_file_id` | LabKey output file ID (injected during ingest) |
| `RIRA_Immune.cellclass` | Broad lineage annotation (T cell, B cell, Myeloid, …) — when present |
| `RIRA_TNK_v2.cellclass` | T/NK subtype annotation — when present |
| `RIRA_Myeloid_v3.cellclass` | Myeloid subtype annotation — when present |
| _(additional RIRA/custom columns)_ | Any other metadata columns present in the LabKey Seurat object |

!!! note "Column normalization"
    The following aliases are normalized at ingest time:

    | Raw column name | Normalized to |
    |---|---|
    | `cellbarcode` | `barcode` |
    | `RIRA_Immune_v2.cellclass` | `RIRA_Immune.cellclass` |

---

### EXPORT_COUNTS — 10x-like matrix directory

**Directory:** `outputs/counts/{sample_id}/{sample_id}_counts/`  
**Produced by:** [`ingest_export`](workflows/ingest-export.md), [`full`](workflows/full-pipeline.md)

Compatible with `Seurat::Read10X()`, `scanpy.read_10x_mtx()`, and similar readers.

| File | Format | Description |
|---|---|---|
| `matrix.mtx` | MatrixMarket sparse | Raw count matrix: rows = genes, columns = cells. |
| `features.tsv` | TSV, no header | Gene names, one per row. Row order matches `matrix.mtx`. |
| `barcodes.tsv` | TSV, no header | Cell barcodes, one per row. Column order matches `matrix.mtx`. |
| `obs_meta.csv` | CSV with index | Cell-level metadata from `seurat[[]]`. Always includes `sample_id`, `species`, `output_file_id`, `barcode`. |

#### Reading in R

```r
counts_dir <- "outputs/counts/SAMPLE_01/SAMPLE_01_counts"
mat <- Seurat::Read10X(counts_dir)
obs  <- read.csv(file.path(counts_dir, "obs_meta.csv"), row.names = 1)
```

#### Reading in Python

```python
import scanpy as sc
adata = sc.read_10x_mtx("outputs/counts/SAMPLE_01/SAMPLE_01_counts",
                         var_names="gene_symbols")
```

---

### GENE_HARMONIZE — Harmonized AnnData directory

**Directory:** `outputs/harmonized/harmonized_outputs/`  
**Produced by:** [`full`](workflows/full-pipeline.md)

| File | Description |
|---|---|
| `{idx}_{species}_harmonized.h5ad` | AnnData for one species (e.g. `00_human_harmonized.h5ad`). Cells × shared ortholog genes, log-normalised. Index = `{sample_id}_{barcode}`. |
| `integration_manifest.csv` | Maps each species file to its `order_index` (integer sort key for scMODAL). Columns: `species`, `h5ad_file`, `order_index`. |
| `shared_genes.csv` | List of shared ortholog gene symbols used across all species. |
| `ortholog_mapping.csv` | Full HomoloGene-derived mapping table (gene symbol, taxon ID, homolog group ID). |
| `n_shared.txt` | Plain integer — count of shared genes. Read by `SCMODAL_INTEGRATE` two-species fast path. |

#### Reading harmonized data in Python

```python
import scanpy as sc, pandas as pd

manifest = pd.read_csv(
    "outputs/harmonized/harmonized_outputs/integration_manifest.csv"
)
adatas = {
    row.species: sc.read_h5ad(f"outputs/harmonized/harmonized_outputs/{row.h5ad_file}")
    for row in manifest.itertuples()
}
```

---

### SCMODAL_INTEGRATE — Model outputs

**Directory:** `outputs/scmodal/model_outputs/`  
**Produced by:** [`full`](workflows/full-pipeline.md) (GPU)

| File | Description |
|---|---|
| `latent_clustered.h5ad` | Concatenated AnnData of all species. Key outputs: `obsm["X_scmodal"]` (n_cells × n_latent), `obsm["X_umap"]`, `obs["leiden"]` cluster labels. `uns["scmodal"]` stores run metadata. |
| `ckpt.pth` | PyTorch checkpoint of the trained scMODAL model. |
| `training_history.csv` | Run-level summary: `n_species`, `n_cells`, `n_genes`, `n_latent`, `training_steps`, `batch_size`, `train_time_seconds`, `eval_time_seconds`, `device`. |
| `run_summary.json` | JSON with `species_order`, `n_cells`, `n_genes`, `n_latent`, `device`. |
| `gpu_info.txt` | Raw `nvidia-smi` output captured at job start. |

#### Reading the latent embedding in Python

```python
import scanpy as sc

adata = sc.read_h5ad("outputs/scmodal/model_outputs/latent_clustered.h5ad")
# Latent coords:  adata.obsm["X_scmodal"]
# Leiden cluster: adata.obs["leiden"]
# UMAP:           adata.obsm["X_umap"]
```

---

### TABULATE — Subject-level summary table

**File:** `outputs/tabulate/subjectIdTable.csv`  
**Produced by:** [`ingest_tabulate`](workflows/ingest-tabulate.md)

A wide-format CSV where each row is one unique combination of subject-level identity columns, and each cell-type column contains the proportion (0–1) of cells assigned to that category.

| Column group | Example name | Description |
|---|---|---|
| Identity columns | `SubjectId`, `Vaccine`, `Timepoint`, `Tissue` | Subject metadata carried from `--tabulate_id_cols` |
| `cDNA_ID` | `cDNA_ID` | Always included — primary sample identifier |
| Cell-type proportions | `RIRA_Immune.cellclass__T cell` | One column per category within each cell-type column |

#### Reading in R

```r
tbl <- read.csv("outputs/tabulate/subjectIdTable.csv")
```

See the [Synthetic Tabulation Walkthrough](vignettes/synthetic-tabulation.md) for a safe, seeded example, and use `example_tabulation_script.rmd` in the repository root as the companion R Markdown notebook.
