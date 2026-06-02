# batch-effect-assessments

`--workflow batch_effect_assessments`

Post-integration assessment of batch mixing in Seurat objects using iLISI, CiLISI, batch/celltype ASW, and optional kBET. Metric processes run in the **GoodWorkflows base image** (`ghcr.io/gwmcelfresh/goodworkflows:latest`). R packages are pre-installed in the system site-library; GitHub-only packages (`scIntegrationMetrics`, `kBET`) install into a writable temp dir on first use.

## Stage-by-stage dataflow

| Stage | Module | Input | Output | Compute |
|---|---|---|---|---|
| INGEST | `rdiscvr/ingest_*` | LabKey / URL / local file | `{sample_id}.rds` | CPU (Rdiscvr image) |
| PREP | `batch_effect_assessments/prep` | Seurat RDS | `{sample_id}_prep.json` | CPU (GoodWorkflows image) |
| ASSESS_ILISI / CILISI / ASW / KBET | separate processes per metric | RDS + prep + reduction | per-metric CSV | CPU; kBET uses `process_kbet` |
| COLLECT | `batch_effect_assessments/collect` | metric CSVs | `{sample_id}_summary.csv`, plot | CPU (GoodWorkflows image) |

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
| `--batch_assessment_default_methods` | `LISI,CiLISI,ASW,CELLTYPE_ASW` | Default methods when row column is empty |
| `--batch_assessment_min_cells_per_batch` | `20` | Minimum cells required per batch |
| `--batch_assessment_kbet_cells_per_batch` | `1000` | Cells per batch after kBET downsampling |
