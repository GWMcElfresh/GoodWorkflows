# Requirements grill: batch_effect_assessments

| Field | Value |
| --- | --- |
| Evolve cycle | `EV-002` |
| CLI value | `batch_effect_assessments` |
| Status | `accepted` |
| Created | 2026-05-27 |
| Accepted | 2026-05-27 |

## User brief (from kickoff)

- **CLI value:** batch effect assessments → proposed `--workflow batch_effect_assessments`
- **Scientific goal:** Assess batch effects in Seurat objects using kBET, iLISI (Integration LISI), and related mixing metrics.
- **Scope:** For LISI, record the number of experimental batches and the LISI score per Seurat object (good mixing ≈ score near batch count). Compute CiLISI when possible. Record kBET scores (rejection rate near 0 is good; acceptance = 1 − rejection, near 1 is good). Record Batch ASW (low batch ASW / high 1−ASW indicates good mixing; high batch ASW indicates residual batch structure).
- **Inputs and samplesheet expectations:** Seurat objects from the ingest workflow and the standard samplesheet. Add a samplesheet parameter for integration/batch-assessment methods (e.g. LISI, CiLISI, kBET, ASW); autofill defaults LISI, CiLISI, and ASW.
- **Tools:** [scIntegrationMetrics](https://github.com/carmonalab/scIntegrationMetrics) (CiLISI, LISI, celltype_ASW); [kBET](https://github.com/theislab/kBET) (kBET).
- **Compute target:** HPC; parallelize under ~36 cores, under 1 TB RAM (hard cap), under ~36 h wall time (fungible—prefer fewer cores if time/RAM allow; wall time up to ~30 days possible but avoid).
- **Required outputs:** Tables and plots of batch-effect assessments per Seurat object.
- **Known constraints:** kBET is very expensive—downsample Seurat to ~1000 cells per batch before kBET (may require reprocessing).
- **Verification target:** User runs local testing via `template/gw` (setup, example data, runner); agent smoketest within package ecosystem (stub-run + `check_workflows.sh` parity).

---

## Recorded answers

| # | Topic | Status | Answer |
| --- | --- | --- | --- |
| 1–4 | Workflow identity | accepted | CLI `batch_effect_assessments`; posthoc; tri-mode ingest; one row = one object |
| 5–10 | Samplesheet / batch metadata | accepted | Full columns; `integration_assessment_methods`; kBET per-row opt-in; `batch_column` on sheet; RIRA celltype inference; mixed ingest OK |
| 11–14 | Seurat prerequisites | accepted | PCA typical; all discovered reductions; min 20 cells/batch; skip metric with NA when labels bad |
| 15–20 | Metrics semantics | accepted | Full metric set; kBET downsample 1000/batch + re-PCA; separate processes |
| 21–25 | Outputs / plots | accepted | Per-sample dir; summary CSV; columnar good/bad/observed bar plots; run-level merge; celltype_asw default on |
| 26–30 | Params / downsampling | accepted | Global params OK; kBET defaults; synthetic test Seurat; container TBD (base_image) |
| 31–35 | Compute / containers | accepted | Per-task SLURM after method review; GoodWorkflows base + uvr/uv venvs; local stub CPU-only |
| 36–39 | Verification / docs | accepted | stub-run + check_workflows + mkdocs; acceptance criteria per Q35; docs + template parity |

---

## 1. Workflow identity

**Q1.** Confirm CLI value: `batch_effect_assessments` (snake_case, matches other saved workflows)?

**Answer:** yes

**Q2.** This workflow is distinct from `integration` (no export/harmonize/scMODAL)—ingest Seurat RDS only, then compute batch-mixing metrics on the **integrated** (or user-provided) embedding?

**Answer:** correct - this is a posthoc assessment of integration. 

**Q3.** Reuse tri-mode ingest modules (`INGEST_LABKEY` / `INGEST_URL` / `INGEST_FILE`) like `make_tcr_vector_database`, or accept only pre-ingested RDS paths on the samplesheet?

**Answer:** reuse the tri-mode ingest

**Q4.** One workflow row = one Seurat object assessment, or also support multi-object joint kBET across a merged object?

**Answer:** one workflow row = one seurat object assessment

---

## 2. Samplesheet contract (drift ledger)

**Q5.** Base columns: keep `sample_id` + tri-mode (`output_file_id` \| `url` \| `path`) + optional `species` as today?

**Answer:** yes, the sample sheets should always have every necessary column, then subset down.

**Q6.** New column name for enabled metrics: `integration_methods`, `batch_metrics`, or other? Format: comma-separated tokens (`LISI,CiLISI,ASW,kBET`) per row?

**Answer:** just the integration methods (which we should call integration assessment methods actually), primarily to avoid kBET as a default. 

**Q7.** Default autofill when column empty: `LISI,CiLISI,ASW` only (kBET opt-in per row or global param)?

**Answer:** kBET should be opt-in, but mostly to avoid supermassive objects, so per row is fine. 

**Q8.** Required Seurat `meta.data` column for **batch** label (e.g. `Batch`, `batch`, `orig.ident`)—fixed name vs samplesheet override column?

**Answer:** we should pass this as a parameter to the sample sheet. batches should be a column in the seurat metadata. 

**Q9.** Required column for **cell type** (CiLISI, celltype ASW): fixed name vs samplesheet override (e.g. `celltype`, `CellType`, RIRA column)?

**Answer:** for these methods, since they run quickly, we should infer which celltypes should be run from the metadata (e.g. if all of the RIRA.Immune_v2.cellclass is T/NK, then infer that RIRA_TNK is the cell type column - we should have this mapping worked out elsewhere in the package)

**Q10.** Mixed ingest modes in one run—in scope for v1?

**Answer:** yes, the ingest should yield a seurat object that we pipe directly to integration. 

### Samplesheet drift surfaces (check when accepted)

- [x] Workflow parser in `workflows/*.nf`
- [x] Samplesheet validator (if any)
- [x] Example samplesheet under `test-data/` or `data/`
- [x] `docs/data-formats.md`
- [x] `nextflow_schema.json`
- [x] Launcher / generator (`template/gw`, `template/cluster`)
- [x] CI smoke samplesheet
- [x] `memory-bank/` references

---

## 3. Seurat object prerequisites

**Q11.** Input objects: post-integration Seurat with a reduced embedding (e.g. `pca` / `harmony` / `scMODAL` latent in reductions), or also accept objects with only PCA on RNA?

**Answer:** objects will typically only have PCA on RNA - discovery of other embeddings is a bonus (and we should default to running on all discovered embeddings)

**Q12.** Which reduction slot drives LISI/kBET/ASW by default (`pca`, `harmony`, user param `--reduction`)?

**Answer:** typically 'pca' but see the discovery above. 

**Q13.** Minimum cell count per batch before skipping metrics or failing the sample?

**Answer:** 20

**Q14.** If batch or celltype labels are missing/constant, fail sample vs skip metric with NA in output table?

**Answer:** yes

---

## 4. Metric semantics

**Q15.** iLISI: report per-cell distribution summary (median, mean) and/or per-dataset scalar; always record `n_batches` used for interpretation?

**Answer:** yes

**Q16.** CiLISI: require celltype labels; skip with logged reason if absent?

**Answer:** yes

**Q17.** kBET: report rejection rate, acceptance rate (1 − rejection), and expected rejection rate if available?

**Answer:** yes

**Q18.** Batch ASW: report raw ASW and/or `1 - ASW` as “mixing score”; same for celltype ASW if computed?

**Answer:** yes

**Q19.** kBET downsampling: target `1000` cells per batch (param override?); stratified by batch; re-run PCA on downsampled object before kBET?

**Answer:** yes

**Q20.** Run metrics sequentially in one R process vs separate processes per metric (resume granularity)?

**Answer:** separate processes if possible - we have memory/time escalation embedded in the slurm profiles, but we should intend to fail (i.e. OOM) fast

---

## 5. Outputs and plots

**Q21.** Published directory pattern under `params.outdir` (e.g. `outputs/batch_effect_assessments/{sample_id}/`)?

**Answer:** yes

**Q22.** Required table artifacts (CSV/TSV): one summary row per sample with all metrics; optional per-cell LISI table?

**Answer:** per-cell LISI is unnecessary.

**Q23.** Required plots: which metrics get static plots (histogram LISI, kBET summary, ASW barplots)? Output format PNG/PDF?

**Answer:** a single columnar bar plot with good, bad, and observed values for each measure (i.e. for LISI a histogram with n = 1 for poor mixing, n = number of batches for good mixing, and then the observed n)

**Q24.** Combined run-level report (single HTML or multi-sample CSV merge) in v1?

**Answer:** yes

**Q25.** Confirm summary table columns (fill required?):

| Column | Required? | Notes |
| --- | --- | --- |
| `sample_id` | | |
| `n_cells` | | before/after downsample |
| `n_batches` | | |
| `batch_column` | | used |
| `reduction` | | |
| `ilisi_median` | | |
| `ilisi_mean` | | |
| `cilisi_median` | | if computed |
| `kbet_rejection_rate` | | if computed |
| `kbet_acceptance_rate` | | |
| `batch_asw` | | |
| `celltype_asw` | | if computed |
| `methods_run` | | |

**Answer:** this is good. celltype_asw should be on by default

---

## 6. Params, downsampling, caching

**Q26.** Global params: `--batch_column`, `--celltype_column`, `--reduction`, `--kbet_cells_per_batch` (default 1000), `--metrics` override?

**Answer:** this is fine - we can adjust defaults via source values later. 

**Q27.** kBET hyperparameters: use package defaults or expose `k0`, `distance`, `n_repeat`?

**Answer:** use package defaults for now

**Q28.** CI/stub-run: synthetic tiny Seurat in `test-data/` with 2 batches × N cells—minimum acceptance?

**Answer:** yeah, would be good.

**Q29.** R package versions pinned in container (scIntegrationMetrics commit/tag, kBET from GitHub)?

**Answer:** Use `ghcr.io/gwmcelfresh/goodworkflows:latest` (published from repo `Dockerfile` via dockerDependencies CI). Assessment processes install scIntegrationMetrics and kBET with **uvr** into a per-task workspace and remove `.uvr-workspace` on exit.

---

## 7. Compute, resume, containers

**Q30.** Proposed HPC budget (parent suggestion): 8–16 CPUs, 128–512 GB RAM, 24–36 h per sample for kBET-off rows; separate label `process_kbet` with higher mem/time when kBET enabled—acceptable?

**Answer:** only if we can parallelize. it may be the case that we need to perform each batch effect assessment in its own slurm task to prevent occupying 8 threads when only a single thread is performing a long running task. I will need you to investigate each method for parallelization opportunities

**Q31.** Parallelism: one SLURM task per samplesheet row (embarrassingly parallel)?

**Answer:** ideally we run one task per slurm task, but this will pend your research on each repository/method

**Q32.** Container: extend **Rdiscvr** image with kBET + scIntegrationMetrics, or new `batch_metrics` image?

**Answer:** I will give you a base GoodWorkflows image to work with - where you can install these packages on the fly using uv for python and uvr for R and work out of venvs. Ensure you clean up venvs afterwards. see status here: https://github.com/GWMcElfresh/GoodWorkflows/tree/base_image (currently not finished) 

**Q33.** Local `template/gw` smoke: CPU-only stub acceptable; real kBET only on HPC profile?

**Answer:** yes, this is fine. 

---

## 8. Docs, schema, verification

**Q34.** Minimum verification sign-off: stub-run + `check_workflows.sh` + mkdocs page + schema params?

**Answer:** yes

**Q35.** Acceptance criteria: e.g. summary CSV has expected columns; plots exist when methods include LISI/ASW; kBET row skipped or NA when not requested?

**Answer:** yes

**Q36.** Update workflow count in `docs/index.md`, `docs/usage.md`, `memory-bank/workflows.md`?

**Answer:** yes, include the templates (including local testing for templates/gw). use a subagent to update the skill such that this question is always yes and you employ the parity skill to make sure the templates stay up to date with all workflows. 

**Q37.** New `docs/workflows/batch-effect-assessments.md` with stage table and metric interpretation glossary?

**Answer:** yes

---

## 9. Quick decisions (optional)

| Topic | Choice (A / B / C) | Notes |
| --- | --- | --- |
| CLI name | A `batch_effect_assessments` / B `batch_effect_assessment` / C other | |
| Ingest | A tri-mode ingest / B path-only RDS / C both | |
| kBET default | A opt-in per row / B global param / C always with downsample | |
| Batch column | A fixed `Batch` / B param / C samplesheet column | |
| Celltype | A required / B optional (skip CiLISI) / C fail | |
| Container | A Rdiscvr extend / B new image / C conda in existing | |
| Reduction | A `pca` / B `harmony` / C param-driven | |

---

## Sign-off

| Role | Name | Date | Notes |
| --- | --- | --- | --- |
| Requester | GW | 5/27 | |
| Agent / implementer | Composer | 2026-05-27 | Requirements accepted for `02-verify-plan` |

**Open blockers:** none
