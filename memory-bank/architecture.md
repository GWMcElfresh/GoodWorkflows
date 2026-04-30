# Architecture

## DSL2 Module Graph

```
┌──────────┐     ┌───────────────┐     ┌────────────────┐     ┌───────────────────┐
│  INGEST  │────▶│ EXPORT_COUNTS │────▶│ GENE_HARMONIZE │────▶│ SCMODAL_INTEGRATE │
└──────────┘     └───────────────┘     └────────────────┘     └───────────────────┘
  rdiscvr/ingest    cellmembrane/       gene_harmonize/         scModal/gpu/
                    seurat/
```

## Entry Point: `main.nf`

A thin launcher that:
1. Includes all three workflow definitions
2. Validates `--workflow` against `['integration', 'ingest_export', 'ingest_tabulate']`
3. Validates required params (`--labkey_base_url`, `--labkey_folder`, `--input`)
4. Dispatches to the selected workflow via a `switch` block
5. Reports completion/error via `workflow.onComplete` and `workflow.onError`

## Workflow Composition

### `INTEGRATION_PIPELINE` (workflows/integration_pipeline.nf)
- **Guard:** Blocks local executor unless `--scmodal_use_cpu true` (CI-only)
- **Channel flow:**
  1. `buildIntegrationPipelineSamplesChannel(samplesheet)` → parses CSV, emits `meta` maps
  2. `INGEST(ch_samples)` → downloads Seurat RDS per sample
  3. `EXPORT_COUNTS(INGEST.out.rds)` → extracts 10x-like counts per sample
  4. `ch_all_count_dirs` = collect all count dirs into a single list
  5. `GENE_HARMONIZE(ch_all_count_dirs)` → cross-species ortholog mapping + normalization
  6. `SCMODAL_INTEGRATE(GENE_HARMONIZE.out.harmonized)` → train scMODAL, cluster

### `INGEST_EXPORT_PIPELINE` (workflows/ingest_export.nf)
- CPU-only, no GPU guard
- **Channel flow:**
  1. `buildIngestExportSamplesChannel(samplesheet)` → meta maps
  2. `INGEST(ch_samples)` → download RDS
  3. `EXPORT_COUNTS(INGEST.out.rds)` → export counts

### `INGEST_TABULATE_PIPELINE` (workflows/ingest_tabulate.nf)
- CPU-only, metadata-only
- **Channel flow:**
  1. `buildIngestTabulateSamplesChannel(samplesheet)` → meta maps
  2. `INGEST_METADATA(ch_samples)` → download per-sample metadata CSVs
  3. Collect all CSVs into a single list
  4. `TABULATE(csvs, id_cols, celltype_cols, parent_col, parent_map)` → `subjectIdTable.csv`

## Config Layering Order

```
base.config  →  profile-specific config (local / slurm / test)
```

- `base.config`: All default params, `workDir` setting
- `local.config`: Podman, local executor, 3 CPUs, 6 GB RAM, maxForks=1
- `slurm.config`: Podman, SLURM executor, per-label resource specs, retry logic
- `slurm_singularity.config`: Apptainer/Singularity instead of Podman
- `test.config`: No containers, local executor, minimal resources (for CI stub-runs)

## Container Strategy

- **Local:** Podman with `--platform linux/amd64`
- **HPC (SLURM):** Docker images pre-pulled as Apptainer SIF files into `${PIPELINE_ROOT}/apptainer-sif/` or `$NXF_SINGULARITY_CACHEDIR`
- **CI:** No containers (`-profile test` disables all container engines)

### Container Images

| Module | Image |
|---|---|
| INGEST, INGEST_METADATA, TABULATE | `ghcr.io/bimberlabinternal/rdiscvr:latest` |
| EXPORT_COUNTS | `ghcr.io/bimberlabinternal/cellmembrane:latest` |
| GENE_HARMONIZE, SCMODAL_INTEGRATE | `ghcr.io/gwmcelfresh/scmodal:sha-37c41f9` (configurable via `params.scmodal_container`) |

## Key Design Decisions

1. **Modules are single-step and independently testable** — each has its own `main.nf` under `modules/local/<category>/`
2. **Workflows compose modules** — workflows are thin orchestrators, not monolithic scripts
3. **Stub blocks for CI** — every process has a `stub:` block so `-stub-run` validates DSL2 wiring without real computation
4. **Samplesheet-driven** — all workflows consume a CSV samplesheet with `sample_id`, `output_file_id`, `species` columns
5. **LabKey auth via `.netrc`** — credentials are never in params; mounted read-only into containers