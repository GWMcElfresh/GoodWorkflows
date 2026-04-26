# Usage

This guide walks through everything needed to set up and run a GoodWorkflows pipeline run on an HPC cluster — from first clone to submitted job — along with local Mac/Linux usage for the CPU workflows.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| **Nextflow ≥ 24.04** | [Install guide](https://www.nextflow.io/docs/latest/getstarted.html) |
| **SLURM + Podman** | Required for `--profile slurm` (HPC). Rootless Podman must be working. |
| **`~/.netrc`** | LabKey/Prime-seq authentication. See note below. |
| **Git** | Needed to clone and sync the repository. |

!!! note "LabKey credentials"
    All workflows authenticate to the LabKey / Prime-seq server via `~/.netrc`. Add an entry like:

    ```
    machine labkey.example.org
    login your_username
    password your_password
    ```

    Replace `labkey.example.org` with your actual server hostname. The file should be `chmod 600`.

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

## 2 — Set up a run directory

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
├── run.sh            ← edit the FILL IN section, then sbatch
```

All outputs will land in subdirectories of the run directory:

```
runs/my_run_name/
├── outputs/          ← published results (RDS, counts, tables, models)
├── work/             ← Nextflow intermediate files (can be deleted after success)
└── logs/             ← nextflow.log + SLURM job logs
```

---

## 3 — Edit the samplesheet

Open `samplesheet.csv` and add one row per sample. All three columns are required:

| Column | Description |
|---|---|
| `sample_id` | Unique identifier used as output filename prefix and directory name. |
| `output_file_id` | LabKey output file ID used by Rdiscvr to fetch the data. |
| `species` | One of the species in `--species_order` (default: `human`, `macaque`, `mouse`). |

```csv
sample_id,output_file_id,species
SAMPLE_01,100001,human
SAMPLE_02,100002,macaque
SAMPLE_03,100003,mouse
```

See [Data Formats → Samplesheet](data-formats.md#samplesheet) for the full schema.

---

## 4 — Configure `run.sh`

Open `run.sh` and fill in the `# FILL IN` section near the top:

```bash
# 1. Choose the workflow
WORKFLOW="ingest_tabulate"   # or: integration, ingest_export

# 2. Set your LabKey coordinates
LABKEY_BASE_URL="https://labkey.example.org"
LABKEY_FOLDER="/My/Project/Folder"

# 3. Point to your Nextflow binary and home directory
NEXTFLOW_BIN="/gscratch/mylab/nextflow"
NXF_HOME="/gscratch/mylab/.nextflow"
```

### Choosing a workflow

| Workflow | What it does | Where to run |
|---|---|---|
| `integration` | Ingest → export counts → harmonize → scMODAL | HPC + GPU (`-profile slurm`) |
| `ingest_export` | Download Seurat RDS + export 10x-like counts | Local Mac or HPC (CPU) |
| `ingest_tabulate` | Download cell metadata → build `subjectIdTable.csv` | Local Mac or HPC (CPU) |

### PIPELINE_ROOT auto-detection

`run.sh` automatically locates the GoodWorkflows checkout by walking up the directory tree from the run directory looking for `main.nf`. As long as `runs/` is a direct subdirectory of the checkout, no configuration is needed. To override:

```bash
PIPELINE_ROOT=/explicit/path/to/GoodWorkflows sbatch run.sh
```

---

## 5 — Submit the job

```bash
# From inside runs/my_run_name/:
sbatch run.sh
```

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

Or run Nextflow directly from the repo root:

```bash
nextflow run main.nf \
  --workflow ingest_tabulate \
  --labkey_base_url https://labkey.example.org \
  --labkey_folder /My/Project/Folder
```

---

## 6 — Container image pre-pull and caching

When running with `-profile slurm` (HPC), every workflow task uses a rootless Podman container. Without coordination, Podman would pull the same multi-GB image in parallel from every node, exhausting disk quota and causing `disk quota exceeded` (exit 125) failures.

GoodWorkflows solves this with a **shared OCI archive store** and a **pre-pull job** that runs before the orchestrator starts.

### How it works

1. `slurm_nextflow.sh` (and `template/run.sh`) submit `scripts/slurm_prepull_images.sh` as a standalone SLURM job.
2. The pre-pull job pulls each image on a **node-local filesystem** (`/tmp`), then saves it as a plain OCI tar archive to `NXF_PODMAN_CACHEDIR` on the shared filesystem. Plain tar writes work fine on NFS/Lustre — no overlay operations.
3. The orchestrator is submitted with `--dependency=afterany:<PREPULL_JOB_ID>` so it always starts.
4. Each task's `beforeScript` checks for the `.tar.done` sentinel in `NXF_PODMAN_CACHEDIR` and loads the archive with `podman load` before running. This skips the registry entirely on subsequent runs.
5. If the archive is missing (e.g. pre-pull failed), tasks fall back to a coordinated locked registry pull.

### The container store

By default, archives are written to the user's configured podman `graphRoot` — the same value returned by:

```bash
podman info --format '{{.Store.GraphRoot}}'
```

This is read from `~/.config/containers/storage.conf`, so every user on the cluster gets their own independent archive store automatically. No shared path needs to be hardcoded or coordinated.

After the first run, that directory contains one archive pair per image:

```
ghcr.io_bimberlabinternal_cellmembrane___latest.tar
ghcr.io_bimberlabinternal_cellmembrane___latest.tar.done
ghcr.io_bimberlabinternal_rdiscvr___latest.tar
ghcr.io_bimberlabinternal_rdiscvr___latest.tar.done
ghcr.io_gwmcelfresh_scmodal-cuda___latest.tar
ghcr.io_gwmcelfresh_scmodal-cuda___latest.tar.done
```

The `.done` sentinels tell tasks the archive is complete and safe to load. The `.tar` files are plain OCI archives you can inspect, copy, or sync with `rsync`.

### Syncing or sharing archives

To copy your archive store to another cluster, or share it with another user:

```bash
# Find your store path
STORE="$(podman info --format '{{.Store.GraphRoot}}')"

# Sync to another cluster
rsync -av "${STORE}/" other-cluster:/path/to/dockerContainers/
```

Then on the target:

```bash
NXF_PODMAN_CACHEDIR=/path/to/dockerContainers sbatch run.sh --workflow full ...
```

### Environment variables

| Variable | Default | Description |
|---|---|---|
| `NXF_PODMAN_CACHEDIR` | *(from `podman info`)* | Shared OCI archive store. Defaults to the user's configured `graphRoot` on the compute node, so each user gets their own store automatically. Override to share archives between users or point to a pre-populated store. |
| `NXF_PODMAN_TMPDIR` | `${SLURM_TMPDIR:-/tmp}` | **Node-local** scratch for overlay layer unpacking. Must NOT be on NFS. |
| `NXF_PODMAN_PULL_LOCK_DIR` | `${NXF_WORK}/.podman-pull-locks` | Shared lock directory coordinating concurrent per-task fallback pulls. |

!!! warning "Overlay storage must be node-local"
    `NXF_PODMAN_TMPDIR` must point to a local filesystem (`/tmp`, `SLURM_TMPDIR`, or a local scratch mount). Setting it to a Lustre/NFS path causes `fuse-overlayfs` to fail silently after downloading blobs — the layer commit step requires xattr/hardlink support. The OCI archive store (`NXF_PODMAN_CACHEDIR`) is plain file I/O and is fine on NFS.

### Updating `scripts/image-manifest.txt`

The pre-pull script discovers images by parsing the Nextflow config. As a fallback (if dynamic discovery returns zero images), it reads `scripts/image-manifest.txt`. Keep this file up to date whenever you add or update a container image:

```text
ghcr.io/bimberlabinternal/cellmembrane:latest
ghcr.io/bimberlabinternal/rdiscvr:latest
ghcr.io/gwmcelfresh/scmodal-cuda:latest
```

One image URI per line; blank lines and `#` comments are ignored.

---

## 7 — Monitor a running job

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

## 8 — Resume after failure

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

## 9 — Reference runs

`slurm_nextflow.sh` in the repository root is an alternative launcher that targets the repository itself as the run context (work dir and logs relative to the checkout). Use it when you prefer not to use the `runs/` pattern:

```bash
# From the GoodWorkflows checkout root:
sbatch slurm_nextflow.sh --workflow integration \
  --labkey_base_url https://labkey.example.org \
  --labkey_folder /My/Project/Folder
```

It can also be submitted from a different directory since it resolves `PIPELINE_ROOT` from its own file path.

---

## See also

- [Workflow details — Integration Pipeline](workflows/integration-pipeline.md)
- [Workflow details — Ingest + Export](workflows/ingest-export.md)
- [Workflow details — Ingest + Tabulate](workflows/ingest-tabulate.md)
- [Parameter reference](parameters.md)
- [Data formats and schemas](data-formats.md)
