# GoodWorkflows

A DSL2 **Nextflow** repository for composing reusable single-cell workflows from small modules and running them on **SLURM + Podman** HPC systems.

📖 **[Full documentation →](https://gwmcelfresh.github.io/GoodWorkflows/)**  
Parameters: [`nextflow_schema.json`](nextflow_schema.json) | Docs source: [`docs/`](docs/)

---

## Repository layout

```text
.
├── main.nf                 # Thin launcher for saved workflows
├── workflows/              # Higher-level reusable workflows
├── modules/local/          # Single-step DSL2 modules
├── configs/                # Base + profile-specific config
├── data/                   # Default repo-local input location
├── template/               # Copyable per-run launcher scaffold
├── outputs/                # Default published results (generated)
├── work/                   # Nextflow work dir (generated)
├── logs/                   # Reports and SLURM logs (generated)
├── slurm_nextflow.sh       # Repo-root HPC launcher
└── slurm_sync_repo.sh      # Fast clone / update job for HPC checkouts
```

## Saved workflows

| Workflow | Purpose |
|---|---|
| `full` | `INGEST -> EXPORT_COUNTS -> GENE_HARMONIZE -> SCMODAL_INTEGRATE` |
| `ingest_export` | Download Seurat objects and export 10x-like counts only |
| `ingest_tabulate` | Download metadata only and build `subjectIdTable.csv` |

Select one with `--workflow`.

---

## Defaults

The repo now uses local, predictable defaults:

- **Input samplesheet:** `./data/samplesheet.csv`
- **Published outputs:** `./outputs`
- **Work directory:** `./work`
- **Reports/logs:** `./logs`

These can still be overridden on the CLI.

---

## Running locally

CPU-friendly workflows can be run directly on macOS or Linux without SLURM:

```bash
nextflow run main.nf \
  --workflow ingest_tabulate \
  --labkey_base_url https://labkey.example.org \
  --labkey_folder /My/Folder
```

```bash
nextflow run main.nf \
  --workflow ingest_export \
  --labkey_base_url https://labkey.example.org \
  --labkey_folder /My/Folder
```

The `full` workflow is intentionally blocked on local CPU execution outside GitHub Actions smoke tests because `SCMODAL_INTEGRATE` needs a GPU-backed SLURM environment.

If needed, you can still force behavior explicitly with `-profile local` or `-profile slurm`.

For a light structural check without running the heavy science stack:

```bash
nextflow run main.nf -profile test -stub-run \
  --workflow ingest_export \
  --labkey_base_url https://labkey.example.org \
  --labkey_folder /My/Folder
```

---

## Running on HPC

### 1. Sync or clone the repo

Recommended: **do this outside the pipeline**, not as a Nextflow module. A pipeline should not mutate its own checkout while it is running.

```bash
sbatch slurm_sync_repo.sh
```

Or target a specific scratch location:

```bash
sbatch --export=ALL,SYNC_TARGET_DIR=/gscratch/mygroup/GoodWorkflows slurm_sync_repo.sh
```

### 2. Choose an HPC entrypoint

For SLURM-based runs, the simplest path is usually to copy the template and fill out `run.sh`. The repo-root wrapper is still available when you want repo-relative outputs or a separate pre-pull job.

| Entry point | Best for | Pre-pull behavior |
|---|---|---|
| `runs/<name>/run.sh` | Recommended routine SLURM runs with a dedicated run directory and checked-in samplesheet template | Runs **inline** inside the same SLURM allocation before `nextflow run` |
| `bash slurm_nextflow.sh ...` | Repo-root launches, automation, or cases where you want image pre-pull isolated first | Submits a **standalone pre-pull job** before the orchestrator |

#### 2A. Recommended: copy the template and submit `run.sh`

```bash
cp -r template runs/my_run_name
cd runs/my_run_name

# edit samplesheet.csv and the FILL IN section in run.sh
sbatch run.sh
```

`run.sh` does perform a container image pre-pull on SLURM, but it does so **inline in the same allocation** before Nextflow starts. For CPU-only local workflows, `bash run.sh` skips SLURM pre-pull entirely.

#### 2B. Alternative: launch from the repository root

```bash
bash slurm_nextflow.sh \
  --workflow full \
  --labkey_base_url https://labkey.example.org \
  --labkey_folder /My/Folder
```

Preferred launch mode: run `bash slurm_nextflow.sh ...` from a login node. In that mode the wrapper submits a standalone container image pre-pull job first, then submits the orchestrator with `--dependency=afterok:<PREPULL_JOB_ID>`. Pre-pull is therefore a hard prerequisite for orchestration.

If you instead use `sbatch slurm_nextflow.sh ...`, the same pre-pull runs inline inside the orchestrator allocation before Nextflow launches. `template/run.sh` also uses inline pre-pull.

GoodWorkflows now keeps the rootless Podman `graphRoot` on node-local scratch and keeps a shared OCI archive cache on `NXF_WORK`. The standalone pre-pull job populates that shared cache first, and each task then loads the required image from the cache into its own node-local Podman store before `podman run`.

#### Podman storage prerequisite

Rootless Podman must not use gscratch, NFS, or other distributed filesystems for `graphRoot`. On exacloud that layout fails at runtime with errors like `crun: open .../overlay/.../merged: Permission denied`.

The pipeline now writes a task-local `storage.conf` automatically. To use it safely, each SLURM allocation must have node-local scratch available through one of these paths:

- `SLURM_TMPDIR` from the requested local disk allocation. This repository already requests `--gres=disk:1028`.
- `NXF_PODMAN_LOCAL_SCRATCH` if your cluster exposes node-local scratch through a different path.

Shared image reuse happens through `${NXF_PODMAN_CACHEDIR:-${NXF_WORK}/.podman-oci-cache}`, which stores plain OCI archive files on shared storage. Those archives are safe on gscratch because they do not rely on rootless overlay mounts.

On exacloud, rootless user sessions are not delegated the `cpu`/`cpuset` cgroup controllers, so Podman cannot honor container CPU or memory limits there. The SLURM profile therefore launches Podman with `--cgroups=disabled` and strips Nextflow's auto-generated `--cpu-shares` / `--memory` flags before `podman run`. CPU and memory limits are still enforced by SLURM for the job allocation.

Per-task ephemeral state (Podman graph root, run root, `TMPDIR`, `XDG_RUNTIME_DIR`) is scoped to `${NXF_PODMAN_LOCAL_SCRATCH:-$SLURM_TMPDIR}/goodworkflows-podman/${SLURM_JOB_ID}` and cleaned up automatically by the `afterScript` hook.

Optional: fast-forward the checkout immediately before launch:

```bash
SYNC_REPO_BEFORE_RUN=true bash slurm_nextflow.sh \
  --workflow full \
  --labkey_base_url https://labkey.example.org \
  --labkey_folder /My/Folder
```

---

## Notes on repo sync strategy

A lightweight **git sync job** is the best fit here:

- ✅ simple and transparent
- ✅ works well on HPC scratch filesystems
- ✅ keeps the pipeline code versioned in Git
- ❌ safer than a self-updating Nextflow process inside the running workflow

So the implemented pattern is:

1. `git clone` once on HPC
2. use `slurm_sync_repo.sh` or `scripts/sync_repo.sh` to fast-forward to the latest `main`
3. launch `run.sh` for routine named runs, or `slurm_nextflow.sh` for repo-root launches

---

## CI testing strategy

GitHub Actions validates the repository in two layers:

1. **Workflow smoke tests** — runs `main.nf` with `-profile test -stub-run` for `full`, `ingest_export`, and `ingest_tabulate`. The `full` workflow smoke test additionally passes `--scmodal_use_cpu true` to bypass the local-executor GPU guard; `SCMODAL_INTEGRATE` runs its stub block, which validates DSL2 wiring without requiring a GPU.
2. **Module smoke tests** — runs each module wrapper under `tests/modules/` so every module is exercised independently.

The `test` profile disables containers and uses the local executor so CI can validate DSL2 wiring quickly without requiring HPC infrastructure.

For container-dependent validation, the repo also includes `scripts/ci/cache_container_images.sh`, which can pre-pull and cache the module images into `.ci/docker-cache/` during GitHub Actions runs.

3. **Docs validation and deploy** — on pull requests and pushes that touch workflows, docs, schema, or docs tooling, GitHub Actions regenerates the `nf-docs` API reference, regenerates synthetic example plots, and runs `mkdocs build --strict`. Pushes to `main` also deploy the site to GitHub Pages.

## Regenerating docs locally

```bash
bash scripts/docs/generate_api_docs.sh
uvx --with matplotlib python scripts/docs/generate_example_plots.py
mkdocs build --strict
```

The published vignette and example plots are driven by the seeded synthetic fixture bundle in `tests/fixtures/synthetic_trial_data/`, so docs and CI do not depend on sensitive or machine-local files.

## License

MIT – see `LICENSE`.
