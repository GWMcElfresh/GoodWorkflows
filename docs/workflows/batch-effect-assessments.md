# batch-effect-assessments

`--workflow batch_effect_assessments`

Post-integration assessment of batch mixing in Seurat objects using iLISI, CiLISI, batch/celltype ASW, and optional kBET. Metric processes run in the **GoodWorkflows base image** (`ghcr.io/gwmcelfresh/goodworkflows:latest`) and install R dependencies on the fly with **uvr** (transient project per task, removed on exit).

## Stage-by-stage dataflow

| Stage | Module | Input | Output | Compute |
|---|---|---|---|---|
| INGEST | `rdiscvr/ingest_*` | LabKey / URL / local file | `{sample_id}.rds` | CPU (Rdiscvr image) |
| PREP | `batch_effect_assessments/prep` | Seurat RDS | `{sample_id}_prep.json` | CPU (GoodWorkflows + uvr) |
| ASSESS_ILISI / CILISI / ASW / KBET | separate processes per metric | RDS + prep + reduction | per-metric CSV | CPU; kBET uses `process_kbet` |
| COLLECT | `batch_effect_assessments/collect` | metric CSVs | `{sample_id}_summary.csv`, plot | CPU (GoodWorkflows + uvr) |

Each discovered embedding (typically `pca`, plus any other reductions on the object) is assessed in **parallel SLURM tasks** (one task boundary per metric × reduction).

## Samplesheet

Required columns per row:

| Column | Required | Description |
|---|---|---|
| `sample_id` | yes | Sample identifier |
| `batch_column` | yes | `meta.data` column holding experimental batch labels |
| `integration_assessment_methods` | no | Comma-separated: `LISI`, `CiLISI`, `ASW`, `CELLTYPE_ASW`, `kBET`. Default when empty: `LISI,CiLISI,ASW,CELLTYPE_ASW` (kBET opt-in per row). **Quote the cell in CSV** when it contains commas (e.g. `"LISI,CiLISI,ASW,CELLTYPE_ASW"`). |
| tri-mode ingest | yes | Exactly one of `output_file_id`, `url`, or `path` |
| `species` | optional | Used by `INGEST_FILE` |

Example: `test-data/batch_effect_assessments/samplesheet.csv`

## Cell type column inference

CiLISI and celltype ASW use the same RIRA hierarchy as tabulate: when parent lineage is homogeneous (e.g. all TNK), the workflow selects the child column (`RIRA_TNK_v2.cellclass`, etc.).

## kBET

When `kBET` is listed in `integration_assessment_methods`, the workflow downsamples to `--batch_assessment_kbet_cells_per_batch` (default 1000) cells per batch (stratified), re-runs PCA on the downsampled object, then runs kBET with package defaults.

## Output

Published under `outputs/batch_effect_assessments/`:

- `{sample_id}_prep.json` — reductions, methods, batch/celltype columns
- `{sample_id}_{reduction}_*.csv` — per-metric tables
- `{sample_id}_summary.csv` — merged metrics per reduction
- `{sample_id}_metrics.png` — reference bar plot (iLISI good/bad/observed when ggplot2 is available)
- `run_summary.csv` — collected summaries across samples (via `collectFile`)

## Parameters

| Param | Default | Description |
|---|---|---|
| `goodworkflows_container` | `ghcr.io/gwmcelfresh/goodworkflows:latest` | Base image for assessment processes |
| `batch_assessment_default_methods` | `LISI,CiLISI,ASW,CELLTYPE_ASW` | Samplesheet default |
| `batch_assessment_min_cells_per_batch` | `20` | Minimum cells per batch |
| `batch_assessment_kbet_cells_per_batch` | `1000` | kBET downsample target |

## Verification

**Fixtures for real / local Podman runs**

| Artifact | Path | Purpose |
|----------|------|---------|
| Committed samplesheet | `test-data/batch_effect_assessments/samplesheet.csv` | Defines `batch_column`, methods, and `path` to RDS |
| Generated Seurat RDS | `test-data/batch_effect_assessments/SMOKE.rds` | Ingest input (not committed; gitignored `*.rds`) |

Generate the RDS once (requires R + Seurat; uses **PBMC3k with mocked RIRA columns**, not `small_rira.rds`):

```bash
Rscript scripts/ci/create_batch_effect_smoke_rds.R
# or
bash scripts/ci/ensure_batch_effect_smoke_fixture.sh
```

If `template/gw/data/pbmc3k_human.rds` exists (from `fetch_example_data.sh`), that subset is reused; otherwise pbmc3k is downloaded via SeuratData.

The RDS must include:

- `Batch` column in `meta.data` (matches samplesheet `batch_column`); **three batches** (`Batch1`–`Batch3`) assigned **at random** per cell (≥20 cells per batch)
- ≥20 cells per batch (`batch_assessment_min_cells_per_batch`)
- At least one reduction (generator runs Normalize → Scale → PCA)
- Mocked RIRA columns for CiLISI / `CELLTYPE_ASW`:
  - `RIRA_Immune.cellclass` — TNK vs Myeloid from PBMC3k cluster groups
  - `RIRA_TNK_v2.cellclass` — CD4 / CD8 for TNK cells
  - `RIRA_Myeloid_v3.cellclass` — mono/DC labels for Myeloid cells

Stub/smoke only needs the file to exist (empty placeholder OK for `-stub-run`).

```bash
nextflow run main.nf -profile test -stub-run \
  --workflow batch_effect_assessments \
  --input test-data/batch_effect_assessments/samplesheet.csv
```

Local scaffold: `bash template/gw/check_workflows.sh --workflow batch_effect_assessments`
