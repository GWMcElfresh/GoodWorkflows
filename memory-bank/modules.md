# Modules

All modules live under `modules/local/`. Each is a single-step DSL2 process with its own `main.nf`.

## Module Catalog

### 1. INGEST
**Path:** `modules/local/rdiscvr/ingest/main.nf`  
**Label:** `process_ingest`  
**Container:** `ghcr.io/bimberlabinternal/rdiscvr:latest`

| | Details |
|---|---|
| **Purpose** | Download a Seurat object from either a public URL (`meta.url`) or LabKey/Prime-seq (`meta.output_file_id`). Auto-detects mode. |
| **Input** | `val(meta)` — map with `id`, `species`, and either `url` or `output_file_id` |
| **Output** | `tuple val(meta), path("{id}.rds")` — downloaded Seurat RDS |
| **Output** | `tuple val(meta), path("{id}_metadata.csv")` — extracted cell metadata |
| **URL mode** | Uses `download.file()` + `readRDS()`. No auth required. |
| **LabKey mode** | Uses `Rdiscvr::DownloadOutputFile()`. Requires `.netrc` mounted at `/root/.netrc`. |
| **Stub** | `touch {id}.rds` + `touch {id}_metadata.csv` |
| **Tag** | `'ingest'` (static — Nextflow 26.04.0 forbids `${meta.id}` in process-scope directives) |
| **publishDir** | `${params.outdir}/ingest` (flattened — no `/{id}` subdirectory) |

### 2. INGEST_METADATA
**Path:** `modules/local/rdiscvr/ingest_metadata/main.nf`  
**Label:** `process_ingest`  
**Container:** `ghcr.io/bimberlabinternal/rdiscvr:latest`

| | Details |
|---|---|
| | **Purpose** | Download only cell metadata (no RDS) via `Rdiscvr::DownloadMetadataForSeuratObject()` |
| | **Input** | `val(meta)` — map with `id`, `output_file_id`, `species` |
| | **Output** | `tuple val(meta), path("{id}_metadata.csv")` |
| | **Auth** | `.netrc` mounted read-only |
| | **Stub** | `printf 'cDNA_ID\n' > {id}_metadata.csv` |
| | **Notes** | Normalizes `cellbarcode` → `barcode`, `RIRA_Immune_v2.cellclass` → `RIRA_Immune.cellclass` |
| | **Tag** | `'ingest-metadata'` (static — Nextflow 26.04.0 constraint) |
| | **publishDir** | `${params.outdir}/ingest` (flattened — no `/{id}` subdirectory) |

### 3. INGEST_URL
**Path:** `modules/local/rdiscvr/ingest_url/main.nf`  
**Label:** `process_ingest_url`  
**Container:** `ghcr.io/bimberlabinternal/rdiscvr:latest`

| | Details |
|---|---|
| | **Purpose** | Download a data file from a public URL. Infers file type from URL suffix and converts to Seurat object. Supports: `.rds` (readRDS), `.csv`/`.tsv`/`.txt` (data.table::fread), `.h5ad` (SeuratDisk::LoadH5Seurat). Generic tables stored as metadata; counts-like matrices auto-built into Seurat. |
| | **Input** | `val(meta)` — map with `id`, `species`, `url` |
| | **Output** | `tuple val(meta), path("{id}.rds")` — converted Seurat RDS |
| | **Output** | `tuple val(meta), path("{id}_metadata.csv")` — extracted cell metadata |
| | **Dependencies** | `data.table` (for CSV/TSV/TXT), `SeuratDisk` (optional, for h5ad), both available in rdiscvr image |
| | **Auth** | None — no `.netrc` mount needed |
| | **Stub** | `touch {id}.rds` + `touch {id}_metadata.csv` |
| | **Tag** | `'ingest_url'` |
| | **publishDir** | `${params.outdir}/ingest` (flattened) |

### 4. EXPORT_COUNTS
**Path:** `modules/local/cellmembrane/seurat/main.nf`  
**Label:** `process_export`  
**Container:** `ghcr.io/bimberlabinternal/cellmembrane:latest`

| | Details |
|---|---|
| **Purpose** | Extract raw counts + cell metadata from a Seurat object into 10x-like matrix directory |
| **Input** | `tuple val(meta), path(rds)` |
| **Output** | `tuple val(meta), path("{id}_counts")` — directory with matrix.mtx, features.tsv, barcodes.tsv, obs_meta.csv |
| **Key param** | `--export_assay` (default: `RNA`) — which Seurat assay to extract |
| **Stub** | Creates directory + touches all 4 expected files |
| **Tag** | `'export-counts'` (static — Nextflow 26.04.0 constraint) |
| **publishDir** | `${params.outdir}/counts` (flattened — no `/{id}` subdirectory) |

### 5. GENE_HARMONIZE
**Path:** `modules/local/gene_harmonize/main.nf`  
**Label:** `process_harmonize`  
**Container:** `${params.scmodal_container}` (default: `ghcr.io/gwmcelfresh/scmodal:sha-37c41f9`)

| | Details |
|---|---|
| **Purpose** | Cross-species gene harmonization: ortholog mapping via mygene HomoloGene, duplicate collapse, normalization, per-species AnnData output |
| **Input** | `path count_dirs` — collected list of all `{id}_counts/` directories |
| **Output** | `path('harmonized_outputs')` — directory containing: |
| | • `{NN}_{species}_harmonized.h5ad` — per-species normalized AnnData |
| | • `integration_manifest.csv` — species order, cell/gene counts |
| | • `ortholog_mapping.csv` — full gene-to-ortholog mapping |
| | • `shared_genes.csv` — shared gene list across species |
| | • `n_shared.txt` — count of shared genes |
| **Species config** | human (9606), macaque (9544), mouse (10090) |
| **Processing** | normalize_total → log1p → z-score (per species) |
| **Stub** | Creates directory + touches all expected output files |

### 6. TABULATE
**Path:** `modules/local/rdiscvr/tabulate/main.nf`  
**Label:** `process_tabulate`  
**Container:** `ghcr.io/bimberlabinternal/rdiscvr:latest`

| | Details |
|---|---|
| **Purpose** | Aggregate per-sample metadata CSVs into a wide subject-level table |
| **Input** | `path(metadata_csvs)` — collected list of all `{id}_metadata.csv` files |
| **Input** | `val(tabulate_id_cols)` — comma-separated ID columns |
| **Input** | `val(tabulate_celltype_cols)` — extra cell-type columns |
| **Input** | `val(tabulate_parent_col)` — parent lineage column |
| **Input** | `val(tabulate_celltype_parent_map)` — `col:parentValue` pairs |
| **Output** | `path('subjectIdTable.csv')` |
| **Standard columns** | Always processes `RIRA_Immune.cellclass`, `RIRA_TNK_v2.cellclass`, `RIRA_Myeloid_v3.cellclass` when present |
| **Hierarchy** | Child columns filtered to rows where parent column matches mapped value |
| **Dedup** | Deduplicates barcodes within each ID group before counting |
| **Stub** | `printf 'cDNA_ID\n' > subjectIdTable.csv` |

### 7. SCMODAL_INTEGRATE
**Path:** `modules/local/scModal/gpu/main.nf`  
**Label:** `process_gpu`  
**Container:** `${params.scmodal_container}`

| | Details |
|---|---|
| **Purpose** | Train scMODAL on harmonized species data, produce latent embedding + Leiden clusters |
| **Input** | `path harmonized_dir` — the `harmonized_outputs/` directory |
| **Output** | `path('model_outputs/')` — directory containing: |
| | • `ckpt.pth` — model checkpoint |
| | • `latent_clustered.h5ad` — combined AnnData with `X_scmodal` embedding + UMAP + Leiden |
| | • `training_history.csv` — training summary |
| | • `gpu_info.txt` — nvidia-smi output |
| | • `run_summary.json` — key run metadata |
| **GPU** | Requires NVIDIA GPU (`nvidia-smi` called at start) |
| **Key params** | `--scmodal_latent`, `--scmodal_training_steps`, `--scmodal_batch_size`, `--scmodal_neighbors`, `--leiden_resolution` |
| **Stub** | Creates directory + touches all expected output files |

## Module Dependency Graph

```
INGEST (LabKey) ──────┐
INGEST_URL (URL) ─────┤
                       ├─▶ EXPORT_COUNTS ──────────────▶ GENE_HARMONIZE ──────────────▶ SCMODAL_INTEGRATE
                       │        │                              │                              │
                       │        ├── {id}_counts/               ├── harmonized_outputs/        ├── model_outputs/
                       │        │   ├── matrix.mtx             │   ├── {NN}_{sp}_harmonized   │   ├── ckpt.pth
                       │        │   ├── features.tsv           │   ├── integration_manifest   │   ├── latent_clustered
                       │        │   ├── barcodes.tsv           │   ├── ortholog_mapping       │   ├── training_history
                       │        │   └── obs_meta.csv           │   ├── shared_genes           │   ├── gpu_info.txt
                       │        └──────────────────────────────│   └── n_shared.txt           │   └── run_summary.json
                       │                                       └──────────────────────────────│
                       │                                                                      │
INGEST_METADATA ──────┤                                                                      │
INGEST_URL ───────────┤                                                                      │
                       ├─▶ TABULATE                                                         │
                       │        │                                                              │
                       │        └── subjectIdTable.csv                                         │
                       │                                                                      │
(INGEST_URL can feed either the integration or tabulate branch; INGEST_METADATA is LabKey-only)