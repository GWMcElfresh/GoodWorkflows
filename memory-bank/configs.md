# Configuration Profiles

## Layering Order

```
nextflow.config
  └── configs/base.config        ← Always loaded
       ├── configs/local.config   ← -profile local
       ├── configs/local-gpu.config ← -profile local_gpu
       ├── configs/slurm.config   ← -profile slurm
       ├── configs/slurm_singularity.config ← -profile slurm_singularity
       └── configs/test.config    ← -profile test
```

---

## base.config

**Always loaded.** Sets all default `params` and `workDir`.

### Key Defaults

| Param | Default | Notes |
|---|---|---|
| `workflow` | `integration` | Default workflow |
| `input` | `./data/samplesheet.csv` | Default samplesheet path |
| `outdir` | `./outputs` | Published results |
| `labkey_base_url` | `''` | Must be set via CLI |
| `labkey_folder` | `''` | Must be set via CLI |
| `species_order` | `human,macaque,mouse` | Comma-separated |
| `export_assay` | `RNA` | Seurat assay to export |
| `scmodal_container` | `ghcr.io/gwmcelfresh/scmodal:latest` | Shared container for harmonize + integrate |
| `scmodal_use_cpu` | `false` | CI-only GPU bypass |
| `scmodal_latent` | `20` | Latent dimensions |
| `scmodal_training_steps` | `10000` | Training iterations |
| `scmodal_batch_size` | `500` | Batch size |
| `scmodal_neighbors` | `30` | KNN neighbors |
| `leiden_resolution` | `0.5` | Leiden clustering resolution |
| `tabulate_id_cols` | `cDNA_ID,SubjectId,Vaccine,Timepoint,Tissue` | ID columns for tabulation |
| `tabulate_celltype_cols` | `''` | Extra cell-type columns |
| `tabulate_parent_col` | `''` | Parent lineage column |
| `tabulate_celltype_parent_map` | `''` | Hierarchy map |
| `repo_sync_url` | `https://github.com/GWMcElfresh/GoodWorkflows.git` | For sync scripts |
| `repo_sync_branch` | `main` | Branch to sync |

### Work Directory
```
workDir = "${projectDir}/work"
```

---

## local-gpu.config (`-profile local_gpu`)

**For local workstations with an NVIDIA GPU (8-12 GB VRAM, 32 GB RAM).**

| Setting | Value |
|---|---|
| Container runtime | Podman with `--gpus all` |
| Executor | local |
| CPUs | 4 |
| Memory | 16 GB |
| Time | 24 hours |
| Max forks | 1 |

### Per-Label Overrides

| Label | CPUs | Memory | Retry |
|---|---|---|---|
| `process_ingest_labkey` | 2 | `4.GB * task.attempt` | Retry on OOM (exit 137), max 2 retries; `.netrc` mount |
| `process_ingest_url` | 2 | `4.GB * task.attempt` | Retry on OOM (exit 137), max 2 retries |
| `process_ingest_file` | 2 | `4.GB * task.attempt` | Retry on OOM (exit 137), max 2 retries |
| `process_export` | 2 | 4 GB | — |
| `process_harmonize` | 2 | 8 GB | — |
| `process_tabulate` | 2 | `4.GB * task.attempt` | Retry on OOM (exit 137), max 2 retries |
| `process_gpu` | 4 | 16 GB | — |

### Auth
`.netrc` mounted at `/root/.netrc:ro` for LabKey-mode ingest processes (INGEST_LABKEY, INGEST_METADATA). Not needed for URL or file-mode samples.

### Design Notes
- `maxForks=1` globally ensures only one process runs at a time — memory is never split across concurrent jobs.
- GPU process gets 16 GB system RAM; VRAM (8-12 GB) is managed by PyTorch inside the container.
- The user is responsible for supplying datasets that fit within available VRAM.
- Sets `params.local_gpu = true` to signal the GPU guard in `INTEGRATION_PIPELINE`.

---

## local.config (`-profile local`)

**For local macOS/Linux development.**

| Setting | Value |
|---|---|
| Container runtime | Podman |
| Executor | local |
| CPUs | 3 |
| Memory | 6 GB |
| Time | 2 hours |
| Max forks | 1 |

### Per-Label Overrides

| Label | Memory | Retry |
|---|---|---|
| `process_ingest_labkey` | `8.GB * task.attempt` | Retry on OOM (exit 137), max 2 retries; `.netrc` mount |
| `process_ingest_url` | `8.GB * task.attempt` | Retry on OOM (exit 137), max 2 retries |
| `process_ingest_file` | `8.GB * task.attempt` | Retry on OOM (exit 137), max 2 retries |
| `process_export` | 6 GB | — |
| `process_harmonize` | 6 GB | — |
| `process_tabulate` | `8.GB * task.attempt` | Retry on OOM (exit 137), max 2 retries |

### Auth
`.netrc` mounted at `/root/.netrc:ro` for LabKey-mode ingest processes (INGEST_LABKEY, INGEST_METADATA). Not needed for URL or file-mode samples.

---

## slurm.config (`-profile slurm`)

**For HPC SLURM execution with Podman.**

> **Note (2026-04-29):** Due to complications with the HPC environment, the `slurm` profile is effectively stubbed/retained for reference but not actively used. The primary HPC profile is `slurm_singularity`. The MCP server should prioritize `local`, `slurm_singularity`, and `test` profiles.

### Global Process Settings

| Setting | Value |
|---|---|
| Container runtime | Podman (rootless, `--userns=keep-id`) |
| Executor | slurm |
| Default CPUs | 1 |
| Default Memory | 8 GB |
| Default Time | 2 hours |
| Queue size | 50 |
| Submit rate | 10/min |
| Poll interval | 2 min |

### Retry Strategy

| Exit Code | Attempts | Delay |
|---|---|---|
| 1 | Up to 3 | `(60 * attempt) + jitter(0-30)` seconds |
| 125 | Up to 5 | `(45 * attempt) + jitter(0-30)` seconds |
| 137 | Up to 5 | `(30 * attempt) + jitter(0-30)` seconds |

### Per-Label Resource Specs

| Label | CPUs | Memory | Time | Max Forks | Queue | Extra |
|---|---|---|---|---|---|---|
| `process_ingest_labkey` | 2 | 64 GB | 8 h | 10 | batch | `--gres=disk:1028`, netrc mount |
| `process_ingest_url` | 2 | 64 GB | 8 h | 10 | batch | `--gres=disk:1028` |
| `process_ingest_file` | 2 | 64 GB | 8 h | 10 | batch | `--gres=disk:1028` |
| `process_export` | 2 | 64 GB | 4 h | 10 | batch | `--gres=disk:1028` |
| `process_harmonize` | 2 | 64 GB | 8 h | 5 | batch | `--gres=disk:1028` |
| `process_tabulate` | 2 | 64 GB | 8 h | 10 | batch | `--gres=disk:1028` |
| `process_gpu` | 4 | 128 GB | 24 h | 2 | gpu | `--gres=disk:1028 --gres=gpu:1` |

### Before/After Scripts
- `beforeScript`: `source configs/slurm.before.sh`
- `afterScript`: `source configs/slurm.after.sh`

---

## slurm_singularity.config (`-profile slurm_singularity`)

**For HPC SLURM execution with Apptainer/Singularity instead of Podman.**

Extends `slurm.config` but replaces Podman with Apptainer/Singularity. Used when the HPC cluster prefers SIF-based container execution.

---

## test.config (`-profile test`)

**For CI smoke tests (GitHub Actions).**

| Setting | Value |
|---|---|
| All container engines | Disabled (podman, docker, singularity, apptainer) |
| Executor | local |
| CPUs | 1 |
| Memory | 2 GB |
| Time | 30 min |
| Container | `null` |

Used with `-stub-run` to validate DSL2 wiring without real computation or containers.

---

## Shell Scripts in configs/

| Script | Purpose |
|---|---|
| `slurm.before.sh` | Pre-task setup for SLURM jobs |
| `slurm.after.sh` | Post-task cleanup for SLURM jobs |
| `slurm.apptainer-before.sh` | Pre-task setup for Apptainer jobs |
| `slurm.apptainer-after.sh` | Post-task cleanup for Apptainer jobs |
| `slurm.podman-local.sh` | Podman configuration for local SLURM testing |