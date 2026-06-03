# batch-effect-assessments

`--workflow batch_effect_assessments`

Post-integration assessment of batch mixing in Seurat objects using iLISI, CiLISI, batch/celltype ASW, and optional kBET. Metric processes run in the **GoodWorkflows base image** (`ghcr.io/gwmcelfresh/goodworkflows:latest`). R packages are pre-installed in the system site-library; GitHub-only packages (`scIntegrationMetrics`, `kBET`) install into a writable temp dir on first use.

## Stage-by-stage dataflow

| Stage | Module | Input | Output | Compute |
|---|---|---|---|---|
| INGEST | `rdiscvr/ingest_*` | LabKey / URL / local file | `{sample_id}.rds` | CPU (Rdiscvr image) |
| PREP | `batch_effect_assessments/prep` | Seurat RDS | `{sample_id}_prep.json` | CPU (GoodWorkflows image) |
| ASSESS_ILISI / CILISI / ASW / KBET | separate processes per metric | RDS + prep + reduction | per-metric CSV | CPU; kBET uses `process_kbet` |
| COLLECT | `batch_effect_assessments/collect` | metric CSVs | `{sample_id}_{reduction}_summary.csv`, plot | CPU (GoodWorkflows image) |

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
- `{sample_id}_{reduction}_cilisi_cells.csv` — per-cell CiLISI values (cell_barcode, cilisi_value, celltype, batch)
- `{sample_id}_{reduction}_asw_cells.csv` — per-cell ASW values (cell_barcode, batch_asw, celltype_asw, batch)
- `{sample_id}_{reduction}_summary.csv` — merged metrics per reduction (one per embedding)
- `{sample_id}_{reduction}_metrics.png` — reference bar plot (iLISI good/bad/observed when ggplot2 is available; one per embedding)
- `{sample_id}_{reduction}_celltype_assessment.png` — stacked histogram of per-cell CiLISI, batch ASW mixing score, and celltype ASW with good/bad region shading
- `run_summary.csv` — collected summaries across samples (via `collectFile`)

## Parameters

| Param | Default | Description |
|---|---|---|
| `--batch_assessment_default_methods` | `LISI,CiLISI,ASW,CELLTYPE_ASW` | Default methods when row column is empty |
| `--batch_assessment_min_cells_per_batch` | `20` | Minimum cells required per batch |
| `--batch_assessment_kbet_cells_per_batch` | `1000` | Cells per batch after kBET downsampling |

## Output Interpretation

### Metric Status Codes

Every metric CSV row includes a `status` column:

| Status | Meaning |
|---|---|
| `ok` | Metric computed successfully — values are real |
| `skipped` | Metric not requested (absent from `integration_assessment_methods`) |
| `na` | Computation failed — check the `message` column for the error text |
| `stub` | CI stub-run placeholder — not real data |

---

### iLISI — Integrated Local Inverse Simpson Index

**What it measures.** For each cell, iLISI computes how many different batch labels are represented among its k-nearest neighbors in the embedding. It reports the median (and mean) LISI score across all cells.

The LISI score ranges from **1** (every neighborhood contains only one batch) to **N** (every neighborhood contains all N batches equally). Higher is better.

| iLISI median | Interpretation |
|---|---|
| **≈ N** (e.g. ≈ 2 for two batches) | Neighborhoods contain all batches equally — **excellent mixing** |
| **> 1, < N** | Partial mixing — higher = better |
| **≈ 1** | Cells only see their own batch — **batches remain separated** |

The summary plot (`{sample_id}_{reduction}_metrics.png`) shows a three-bar reference chart:

```
  ^
  |   ██
  |   ██  ██
  |   ██  ██
  |   ██  ██        ██
  |   ██  ██        ██
  +---█████████----------->
    poor   good  observed
   (1)   (N_batches)  (ilisi_median)
```

- **poor_mixing (1)**: Baseline for no mixing
- **good_mixing (N_batches)**: Target — all batches equally represented
- **observed (ilisi_median)**: Your result — ideal if near `good_mixing`

---

### CiLISI — Conditional iLISI (by Cell Type)

**What it measures.** Same logic as iLISI but computed *within each cell type* and then aggregated. This controls for the confound that different cell types may naturally come from different batches (e.g., batch 1 has only T cells, batch 2 has only B cells). CiLISI asks: *within the same cell type, how well are batches mixed?*

| CiLISI median | Interpretation |
|---|---|
| **> 1** | Within each cell type, batches mix well — **biologically meaningful integration** |
| **≈ 1** | Within each cell type, cells cluster by batch — could indicate batch-specific technical effects rather than biology |

**Check `status` and `celltype_column`:** If status is `skipped` and message says "No inferable celltype column", the Seurat object has no RIRA cell-type hierarchy columns. Without cell-type labels, CiLISI cannot separate biological from technical variation.

---

### ASW — Average Silhouette Width (Batch and Celltype)

Silhouette width measures how well each cell fits within its assigned group vs. the nearest neighboring group. Range is [-1, 1]. The module computes two variants:

#### Batch ASW (`batch_asw`)

Treats batch labels as the grouping variable. Positive values mean cells are closer to their own batch than to other batches.

| batch_asw | Batch mixing score (1 − batch_asw) | Interpretation |
|---|---|---|
| **< 0** | > 1.0 | Cells are closer to *other* batches — very well mixed (may risk over-correction) |
| **≈ 0** | ≈ 1.0 | Batches overlap randomly — **good mixing** |
| **> 0** | < 1.0 | Cells stick with their own batch — batch effect present |
| **≈ 1** | ≈ 0 | Batches are completely separated — **strong batch effect** |

The `batch_mixing_score` column (converted to 0–2 scale as `1 − batch_asw`) is a convenience alias: > 0.5 suggests good mixing, < 0.5 suggests poor mixing.

#### ASW downsampling (large objects)

Silhouette width builds an O(n^2) distance matrix. When the object has more than 50,000 cells, the ASW module automatically down-samples using **stratified sampling** (by batch for batch ASW, by celltype for celltype ASW) to stay within R's vector length limit. The down-sampling count is reported in the `message` column of the summary CSV. Note that the per-cell `asw_cells.csv` reflects only the down-sampled cells when down-sampling occurs.

#### Celltype ASW (`celltype_asw`)

Treats cell-type labels as the grouping variable. Used as a biological preservation check.

| celltype_asw | Interpretation |
|---|---|
| **> 0, near 1** | Cells of the same type are tightly clustered — **biological identity preserved** |
| **≈ 0** | Cell types overlap in the embedding — biological signal may be degraded |
| **< 0** | Cells are closer to wrong cell types — **biological structure disrupted** |

#### The ASW tension

Good integration requires **batch ASW low** (batches mixed) while **celltype ASW high** (cell types preserved). Reading them together:

| batch_asw | celltype_asw | Likely diagnosis |
|---|---|---|
| ≤ 0 | ≥ 0.2 | Good integration — batches mix, biology preserved |
| > 0 | ≥ 0.2 | Weak correction — batches remain, biology intact |
| ≤ 0 | < 0 | Over-correction — batches mixed but biological structure lost |
| > 0 | < 0 | Both batch effect and biological degradation |

---

### kBET — k-Nearest Neighbor Batch Effect Test

*Opt-in.* Uses a chi-squared test on local batch-label distributions. Reports the **rejection rate**: the fraction of neighborhoods where the batch distribution significantly differs from the global.

| kbet_rejection_rate | kbet_acceptance_rate (1 − rejection) | Interpretation |
|---|---|---|
| **≈ 0.0 (0%)** | ≈ 1.0 (100%) | No batches detected as different — **excellent mixing** |
| **0.0 – 0.2** | 0.8 – 1.0 | Good |
| **0.2 – 0.4** | 0.6 – 0.8 | Moderate |
| **> 0.4** | < 0.6 | Poor — **strong batch effect** |
| **≈ 1.0 (100%)** | ≈ 0.0 | Every neighborhood is batch-enriched — complete separation |

Compare `kbet_rejection_rate` to `kbet_expected_rejection_rate` (the null expectation). If observed exceeds expected, mixing is worse than random. If observed is below expected, mixing is better than random.

---

### Decision Framework

Use this rubric to summarize integration quality from a `{sample_id}_{reduction}_summary.csv`:

| Signal | Green (good) | Yellow (inspect) | Red (fix needed) |
|---|---|---|---|
| iLISI median | Near N batches | Middle of 1–N | ≈ 1 |
| CiLISI median | > 1 | = 1 (could be real cell-type-by-batch) | Skipped (no celltype column) |
| batch ASW mixing score | ≥ 0.5 | 0.3 – 0.5 | < 0.3 |
| celltype ASW | ≥ 0.2 | 0 – 0.2 | < 0 (degraded) |
| kBET acceptance | > 0.9 | 0.6 – 0.9 | < 0.6 |

---

### Celltype Assessment Plot (`{sample_id}_{reduction}_celltype_assessment.png`)

When per-cell data is available, the collect stage generates a **stacked histogram** with up to three panels, each showing the distribution of cell-level scores with shaded good/bad regions.

#### Panel 1: CiLISI Distribution

Shows the distribution of per-cell CiLISI values. The x-axis is the CiLISI score (range 1 to N_batches+).

| Region | Shading | Meaning |
|--------|---------|---------|
| \[1, 1.5) | Red (low alpha) | Poor mixing — within each celltype, neighborhoods are dominated by a single batch |
| \[1.5, ∞) | Green (low alpha) | Good mixing — batches are well-mixed within each celltype |

The dashed vertical line marks the median CiLISI score, annotated with its value.

#### Panel 2: Batch ASW Mixing Score (1 - batch ASW)

The batch ASW is converted to a mixing score (1 - ASW, range 0–2) where higher is better.

| Region | Shading | Meaning |
|--------|---------|---------|
| \[0, 0.5) | Red (low alpha) | Poor mixing — cells cluster by batch |
| \[0.5, 2\] | Green (low alpha) | Good mixing — batches overlap |

The dashed vertical line marks the mean mixing score.

#### Panel 3: Celltype ASW

Shows the distribution of per-cell celltype silhouette widths. Positive = cells near their own celltype cluster.

| Region | Shading | Meaning |
|--------|---------|---------|
| \[-1, 0) | Red (low alpha) | Biological structure disrupted — cells closer to wrong celltype |
| \[0, 0.2) | Yellow (low alpha) | Neutral — celltypes weakly separated or overlapping |
| \[0.2, 1\] | Green (low alpha) | Biological identity preserved — cells of the same type are tightly clustered |

The dashed vertical line marks the mean celltype ASW.

---

**A note on multiple reductions.** The workflow assesses every embedding found on the Seurat object (PCA, harmony, scmodal, UMAP, t-SNE, in priority order). Compare metrics across reductions: if PCA shows poor mixing but harmony/UMAP show good mixing, the batch correction method worked as intended. If all reductions show poor mixing, the batch effect may be strong enough to resist correction.
