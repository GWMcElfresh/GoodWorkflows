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

## 2 — Choose an HPC entrypoint

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
nextflow run main.nf \
  --workflow ingest_tabulate \
  --labkey_base_url https://labkey.example.org \
  --labkey_folder /My/Project/Folder
```

---

## 6 — Container image pre-pull and caching

When running with `-profile slurm` (HPC), every workflow task uses a rootless Podman container. Without coordination, Podman would pull the same multi-GB image in parallel from every node, exhausting disk quota and causing `disk quota exceeded` (exit 125) failures.

GoodWorkflows solves this with a **pre-pull job** that pulls all images before the orchestrator starts, exports them into a shared OCI archive cache on `NXF_WORK`, and keeps each task's rootless Podman `graphRoot` on node-local scratch.

### Podman storage prerequisite

GoodWorkflows solves this by splitting Podman storage into two parts:

1. A node-local Podman `graphRoot` and `runroot` under `${NXF_PODMAN_LOCAL_SCRATCH:-$SLURM_TMPDIR}/goodworkflows-podman/${SLURM_JOB_ID}`.
2. A shared OCI archive cache under `${NXF_PODMAN_CACHEDIR:-${NXF_WORK}/.podman-oci-cache}`.

This matters because rootless Podman overlay storage must not live on gscratch, NFS, or other distributed filesystems. On exacloud that design fails at runtime with errors like `crun: open .../overlay/.../merged: Permission denied`.

The pipeline now generates a task-local `storage.conf` automatically. You do not need to point your personal `~/.config/containers/storage.conf` at gscratch anymore.

To use the generated local storage safely, each SLURM allocation must expose node-local scratch through one of these paths:

- `SLURM_TMPDIR`, which should be present when local disk is allocated. This repository already requests `--gres=disk:1028`.
- `NXF_PODMAN_LOCAL_SCRATCH`, if your site uses a different node-local scratch path.

The shared OCI archive cache remains on `NXF_WORK` because plain archive files are safe on shared storage even though rootless overlay mounts are not.

On exacloud, rootless user sessions are not delegated the `cpu` or `cpuset` cgroup controllers. That means a plain `podman run --cpu-shares ... --memory ...` fails with `crun: the requested cgroup controller 'cpu' is not available`. The SLURM profile avoids this by launching Podman with `--cgroups=disabled` and stripping Nextflow's auto-generated Podman resource flags before container startup. Scheduler-enforced CPU and memory limits still come from SLURM.

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

the pre-pull still happens before Nextflow starts, but it runs **inline inside the orchestrator allocation** rather than as a separate job. `template/run.sh` also uses inline pre-pull.

### How it works

1. `scripts/slurm_prepull_images.sh` (or the inline pre-pull block) runs on a compute node.
2. It creates a task-local Podman store under `${NXF_PODMAN_LOCAL_SCRATCH:-$SLURM_TMPDIR}/goodworkflows-podman/${SLURM_JOB_ID}`.
3. Each image is pulled into that node-local store and exported to `${NXF_PODMAN_CACHEDIR}` as an OCI archive.
4. Each task's `beforeScript` creates its own node-local Podman store, loads the required OCI archive from shared storage, strips Nextflow's Podman CPU/memory cgroup flags for rootless runs, and falls back to a locked registry pull only if the archive is missing.
5. The `afterScript` removes the task-local Podman directory when the task finishes.

### Environment variables

| Variable | Default | Description |
|---|---|---|
| `NXF_PODMAN_LOCAL_SCRATCH` | unset | Optional override for the node-local scratch base used for Podman graphroot and runroot. |
| `NXF_PODMAN_CACHEDIR` | `${NXF_WORK}/.podman-oci-cache` | Shared OCI archive cache populated by pre-pull and consumed by tasks on other nodes. |
| `NXF_PODMAN_PULL_LOCK_DIR` | `${NXF_WORK}/.podman-pull-locks` | Shared lock directory coordinating concurrent per-task fallback pulls. |

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

## 9 — Alternative repo-root launcher

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
