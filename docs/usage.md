# Usage

This guide walks through everything needed to set up and run a GoodWorkflows pipeline run on an HPC cluster — from first clone to submitted job — along with local Mac/Linux usage for the CPU workflows.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| **Nextflow ≥ 24.04** | [Install guide](https://www.nextflow.io/docs/latest/getstarted.html) |
| **SLURM + Apptainer** | Required for `-profile slurm_singularity` (HPC). Apptainer (≥ 1.0) must be installed or loadable via `module load apptainer`. |
| **`~/.netrc`** | LabKey/Prime-seq authentication (only needed for LabKey-mode samples). See note below. |
| **Git** | Needed to clone and sync the repository. |

!!! note "LabKey credentials"
    Samples using `output_file_id` authenticate to the LabKey / Prime-seq server via `~/.netrc`. Add an entry like:

    ```
    machine labkey.example.org
    login your_username
    password your_password
    ```

    Replace `labkey.example.org` with your actual server hostname. The file should be `chmod 600`. Samples using `url` or `path` do **not** require `.netrc` or LabKey credentials.

---

## 1 — Clone the repository

On your HPC login node (or locally):

```bash
git clone https://github.com/GWMcElfresh/GoodWorkflows.git
cd GoodWorkflows
```

### Keeping the repo up to date on HPC

Submit the lightweight sync job before each run to pull the latest changes:

```bash
sbatch slurm_sync_repo.sh
```

Or run the sync script directly (requires Git in `$PATH`):

```bash
bash scripts/sync_repo.sh "${PWD}"
```

---

## 2 — Choose an ingest mode for each sample

Every sample row must populate **exactly one** ingest column:

| Column | When to use | Requires |
|---|---|---|
| `output_file_id` | Data lives on a LabKey / Prime-seq server | `--labkey_base_url`, `--labkey_folder`, `~/.netrc` |
| `url` | Publicly downloadable RDS / h5ad URL | Only the URL itself |
| `path` | Local file already present on disk | Only the filepath |

!!! tip "Mixed-sample sheets are supported"
    You can mix LabKey, URL, and file samples in the same `samplesheet.csv`. The pipeline dispatches each row to the correct ingest module automatically.

See [Data Formats → Samplesheet](data-formats.md#samplesheet) for the complete column specification.

---

## 3 — Choose an HPC entrypoint

Two SLURM launch patterns are supported:

| Entry point | Best for | Where outputs/logs live | Pre-pull behavior |
|---|---|---|---|
| `runs/<name>/run.sh` | Recommended routine runs with a dedicated run directory and editable per-run config | Under `runs/<name>/` | **Inline** inside the same SLURM allocation before `nextflow run` |
| `bash slurm_nextflow.sh ...` | Repo-root launches, automation, or cases where you want image pre-pull isolated first | Relative to the repository checkout | **Standalone pre-pull job** submitted before the orchestrator |

### Template run directory (recommended for most SLURM runs)

Each run lives in its own directory under `runs/`. The `runs/` tree is gitignored, so nothing in it is ever committed.

```bash
# From inside the GoodWorkflows checkout:
cp -r template runs/my_run_name
cd runs/my_run_name
```

The copied directory contains everything needed for a self-contained run:

```
runs/my_run_name/
├── samplesheet.csv   ← edit this
├── run.sh            ← edit the FILL IN section, then sbatch; performs inline pre-pull on SLURM
```

All outputs will land in subdirectories of the run directory:

```
runs/my_run_name/
├── outputs/          ← published results (RDS, counts, tables, models)
├── work/             ← Nextflow intermediate files (can be deleted after success)
└── logs/             ← nextflow.log + SLURM job logs
```

---

## 4 — Edit the samplesheet

Open `samplesheet.csv` and add one row per sample. Required columns: `sample_id`, `species`, plus exactly one of `output_file_id`, `url`, or `path`.

```csv
sample_id,output_file_id,url,path,species
SAMPLE_LABKEY,100001,,,human
SAMPLE_URL,,https://example.org/data.rds,,macaque
SAMPLE_FILE,,,/home/user/data/mydata.h5ad,mouse
```

### Required parameters (LabKey mode only)

| Parameter | Description |
|---|---|
| `--labkey_base_url` | LabKey server base URL (e.g. `https://labkey.example.org`) |
| `--labkey_folder` | LabKey folder path (e.g. `/My/Project/Folder`) |

These parameters are **only required** for rows using `output_file_id`. URL and file mode rows do not need them.

---

## 5 — Configure `run.sh`

Open `run.sh` and fill in the `# FILL IN` section near the top:

```bash
# 1. Choose the workflow
WORKFLOW="ingest_tabulate"   # or: integration, ingest_export

# 2. Set your LabKey coordinates (only needed for LabKey-mode samples)
LABKEY_BASE_URL="https://labkey.example.org"
LABKEY_FOLDER="/My/Project/Folder"

# 3. Point to your Nextflow binary and home directory
NEXTFLOW_BIN="/gscratch/mylab/nextflow"
NXF_HOME="/gscratch/mylab/.nextflow"
```

!!! tip "LabKey-free runs"
    If all your samples use `url` or `path`, set `LABKEY_BASE_URL=""` and `LABKEY_FOLDER=""` in `run.sh`. The pipeline will skip LabKey authentication entirely.

### Choosing a workflow

| Workflow | What it does | Where to run |
|---|---|---|
| `integration` | Ingest → export counts → harmonize → scMODAL | HPC + GPU (`-profile slurm`) |
| `ingest_export` | Download/load Seurat RDS + export 10x-like counts | Local Mac or HPC (CPU) |
| `ingest_tabulate` | Download/load cell metadata → build `subjectIdTable.csv` | Local Mac or HPC (CPU) |

### PIPELINE_ROOT auto-detection

`run.sh` automatically locates the GoodWorkflows checkout by walking up the directory tree from the run directory looking for `main.nf`. As long as `runs/` is a direct subdirectory of the checkout, no configuration is needed. To override:

```bash
PIPELINE_ROOT=/explicit/path/to/GoodWorkflows sbatch run.sh
```

---

## 6 — Submit the job

```bash
# From inside runs/my_run_name/:
sbatch run.sh
```

For template-based SLURM runs, `run.sh` does perform a container image pre-pull, but it happens **inline in the same allocation** before `nextflow run`. It does not submit a separate pre-pull job.

Pass extra Nextflow parameters as positional arguments to `sbatch`:

```bash
# Override species order for this run
sbatch run.sh --species_order human,macaque

# Override the work directory
NXF_WORK=/scratch/mylab/work sbatch run.sh
```

### Running locally (CPU workflows only)

For `ingest_export` and `ingest_tabulate` you can run without SLURM:

```bash
# From inside runs/my_run_name/:
bash run.sh
```

Local `bash run.sh` runs do not use SLURM and therefore do not perform the SLURM pre-pull step.

Or run Nextflow directly from the repo root:

```bash
# LabKey mode
nextflow run main.nf \
  --workflow ingest_tabulate \
  --labkey_base_url https://labkey.example.org \
  --labkey_folder /My/Project/Folder

# URL mode (no LabKey required)
nextflow run main.nf \
  --workflow ingest_tabulate \
  --input data/samplesheet_url.csv

# File mode (no LabKey required)
nextflow run main.nf \
  --workflow ingest_export \
  --input data/samplesheet_file.csv
```

---

## 7 — Container image pre-pull and SIF cache

When running with `-profile slurm_singularity` (HPC), every workflow task uses an Apptainer SIF container. Without a pre-pull step, Apptainer would attempt to convert each docker image on every compute node simultaneously, hitting registry rate-limits and wasting time. GoodWorkflows solves this with a mandatory pre-pull that converts all required docker images to SIF files once, storing them in a shared directory (`NXF_SINGULARITY_CACHEDIR`) before any task starts.

| Context | What happens | SIF location |
|---|---|---|
| **Pre-pull job** | `apptainer pull docker://<image>` writes a `.img` SIF file; existing SIFs are skipped | `NXF_SINGULARITY_CACHEDIR` (shared NFS) |
| **Task execution** | Nextflow passes the pre-built SIF to `apptainer exec`; no conversion needed | Same shared directory |

### Apptainer SIF cache

SIF files land in `${PIPELINE_ROOT}/apptainer-sif/` by default. This directory must be on a shared filesystem visible to all compute nodes (gscratch is fine). Override with:

```bash
export NXF_SINGULARITY_CACHEDIR=/home/exacloud/gscratch/mylab/singularity-sifs
bash slurm_nextflow.sh --workflow ingest_tabulate ...
```

`APPTAINER_CACHEDIR` (the OCI blob/layer cache set in `~/.bashrc`) is a separate directory used internally by Apptainer to avoid re-downloading image layers. It is passed through to compute nodes automatically; no extra configuration is needed.

### Launch modes

Recommended for routine named runs:

```bash
sbatch run.sh
```

This performs pre-pull inline inside the same allocation before Nextflow starts.

When you specifically want pre-pull as a separate job first:

```bash
bash slurm_nextflow.sh --workflow integration ...
```

This submits a standalone pre-pull SLURM job first, then submits the orchestrator with `--dependency=afterok:<PREPULL_JOB_ID>`. Pre-pull is a hard prerequisite for orchestration.

If you instead run:

```bash
sbatch slurm_nextflow.sh --workflow integration ...
```

the pre-pull still happens before Nextflow starts, but it runs **inline inside the orchestrator allocation** rather than as a separate job.

### How it works

1. `slurm_nextflow.sh` resolves `NXF_SINGULARITY_CACHEDIR` (defaulting to `${PIPELINE_ROOT}/apptainer-sif`) and exports it.
2. `scripts/slurm_prepull_apptainer.sh` (or the inline pre-pull block) runs on a compute node. It converts each docker image to a SIF file via `apptainer pull <sif_path>.tmp docker://<image>`, then atomically renames the `.tmp` file on success. Any `*.img.tmp` partials left by an interrupted pull are removed by an `EXIT` trap. Existing SIF files are skipped.
3. Nextflow's `singularity.cacheDir` (set to `NXF_SINGULARITY_CACHEDIR`) tells Nextflow where to look for the pre-built SIF files. Each task launches as `apptainer exec <sif_path> ...`.
4. `configs/slurm.apptainer-before.sh` (sourced by each task's `beforeScript`) loads the `apptainer` module and prints diagnostics. There is nothing to clean up per-task; SIF files are persistent shared cache.

### Environment variables

| Variable | Default | Description |
|---|---|---|
| `NXF_SINGULARITY_CACHEDIR` | `${PIPELINE_ROOT}/apptainer-sif` | Directory where pre-built SIF files are stored. Must be on shared NFS visible to all compute nodes. |
| `APPTAINER_CACHEDIR` | set in `~/.bashrc` | OCI blob/layer cache used by Apptainer internally during `apptainer pull`. Separate from the SIF output directory. |
| `NXF_APPTAINER_PULL_LOCK_DIR` | `${NXF_WORK}/.apptainer-pull-locks` | Lock directory coordinating concurrent pulls in the pre-pull job. |

### Updating `scripts/image-manifest.txt`

The pre-pull script discovers images by parsing the Nextflow config. As a fallback (if dynamic discovery returns zero images), it reads `scripts/image-manifest.txt`. Keep this file up to date whenever you add or update a container image:

```text
ghcr.io/bimberlabinternal/cellmembrane:latest
ghcr.io/bimberlabinternal/rdiscvr:latest
ghcr.io/gwmcelfresh/scmodal:latest
```

One image URI per line; blank lines and `#` comments are ignored.

---

## 8 — Monitor a running job

### Live log

```bash
tail -f runs/my_run_name/logs/nextflow.log
```

### SLURM job status

```bash
squeue -u "${USER}"
```

### HTML report

After the pipeline completes, open `logs/report.html` in a browser for a full per-process summary (CPU time, memory usage, wall time).

---

## 9 — Resume after failure

`run.sh` (and `slurm_nextflow.sh`) always pass `-resume` to Nextflow. Simply resubmit the job after fixing any issues:

```bash
sbatch run.sh
```

Nextflow will skip all already-completed steps and continue from where it left off.

!!! tip "When to clear the work directory"
    `work/` can be deleted to force a full re-run, or to reclaim disk space after a successful run:

    ```bash
    rm -rf runs/my_run_name/work
    ```

---

## 10 — Alternative repo-root launcher

`slurm_nextflow.sh` in the repository root is the alternative launcher that targets the checkout itself as the run context (work dir and logs relative to the repo). Use it when you do not want the `runs/` pattern, or when you want the pre-pull submitted as its own SLURM job before orchestration starts:

```bash
# From the GoodWorkflows checkout root:
bash slurm_nextflow.sh --workflow integration \
  --labkey_base_url https://labkey.example.org \
  --labkey_folder /My/Project/Folder
```

If you use `sbatch slurm_nextflow.sh ...`, it is still valid, but the pre-pull runs inline inside the orchestrator allocation instead of as a separate job.

It can also be launched from a different directory since it resolves `PIPELINE_ROOT` from its own file path.

---

## See also

- [Workflow details — Integration Pipeline](workflows/integration-pipeline.md)
- [Workflow details — Ingest + Export](workflows/ingest-export.md)
- [Workflow details — Ingest + Tabulate](workflows/ingest-tabulate.md)
- [Parameter reference](parameters.md)
- [Data formats and schemas](data-formats.md)