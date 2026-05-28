# GoodWorkflows

A DSL2 **Nextflow** repository for composing reusable single-cell workflows from small modules and running them on **SLURM + Apptainer** HPC systems.

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

| Workflow | Purpose | Compute |
|---|---|---|
| `integration` | `INGEST -> EXPORT_COUNTS -> GENE_HARMONIZE -> SCMODAL_INTEGRATE` | GPU |
| `ingest_export` | Download Seurat objects and export 10x-like counts only | CPU |
| `ingest_tabulate` | Download metadata only and build `subjectIdTable.csv` | CPU |
| `nmf_vae` | Ingest, export counts, merge, train NMF-VAE | GPU |
| `gex_mil` | Ingest, export counts, merge, train scVI + attention-MIL | GPU |
| `tcr_mil` | Ingest, quantify TCRs via tcrClustR, train BertTCR MIL | GPU |
| `tcr_epitope` | Ingest, quantify TCRs, embed clones with ESM-2, predict epitope binding | GPU |

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

The `integration` workflow is intentionally blocked on local CPU execution outside GitHub Actions smoke tests because `SCMODAL_INTEGRATE` needs a GPU-backed SLURM environment.

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
  --workflow integration \
  --labkey_base_url https://labkey.example.org \
  --labkey_folder /My/Folder
```

Preferred launch mode: run `bash slurm_nextflow.sh ...` from a login node. In that mode the wrapper submits a standalone Apptainer SIF pre-pull job first, then submits the orchestrator with `--dependency=afterok:<PREPULL_JOB_ID>`. Pre-pull is therefore a hard prerequisite for orchestration.

If you instead use `sbatch slurm_nextflow.sh ...`, the same pre-pull runs inline inside the orchestrator allocation before Nextflow launches. `template/run.sh` also uses inline pre-pull.

GoodWorkflows pre-pulls every required docker image as an Apptainer SIF file into `${PIPELINE_ROOT}/apptainer-sif/` (or `$NXF_SINGULARITY_CACHEDIR` if set). The standalone pre-pull job populates this shared cache before any tasks start; each task finds the SIF there directly with no conversion overhead.

#### Apptainer SIF cache

The pipeline converts each docker image to a SIF file once and stores it in `${PIPELINE_ROOT}/apptainer-sif/` (shared NFS). Override with:

```bash
export NXF_SINGULARITY_CACHEDIR=/home/exacloud/gscratch/<lab>/singularity-sifs
bash slurm_nextflow.sh --workflow ingest_tabulate ...
```

`APPTAINER_CACHEDIR` (the OCI blob/layer cache, typically set in `~/.bashrc`) is passed through to compute nodes automatically and speeds up repeated pulls of the same image layers.

Optional: fast-forward the checkout immediately before launch:

```bash
SYNC_REPO_BEFORE_RUN=true bash slurm_nextflow.sh \
  --workflow integration \
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

1. **Workflow smoke tests** — runs `main.nf` with `-profile test -stub-run` for `integration`, `ingest_export`, and `ingest_tabulate`. The `integration` workflow smoke test additionally passes `--scmodal_use_cpu true` to bypass the local-executor GPU guard; `SCMODAL_INTEGRATE` runs its stub block, which validates DSL2 wiring without requiring a GPU.
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

## Base Docker image

The repository publishes a multi-runtime base image to GHCR at
`ghcr.io/gwmcelfresh/goodworkflows:latest` with **Python** (managed by
[`uv`](https://github.com/astral-sh/uv)), **R** (plus
[`uvr`](https://github.com/nbafrank/uvr)), and **Rust** pre-installed.

The image is built via [GWMcElfresh/dockerDependencies](https://github.com/GWMcElfresh/dockerDependencies)
reusable workflows (same pattern as [MIL-ton CI](https://github.com/GWMcElfresh/MIL-ton/blob/main/.github/workflows/ci.yml)):

- `base-deps:YYYY-MM` — monthly foundation layer
- `deps:<hash-YYYY-MM>` — incremental dependency cache
- `:latest` — runtime image published on pushes to `main`

### Build args

| Arg | Default | Description |
|-----|---------|-------------|
| `PYTHON_VERSION` | `3.12` | uv-managed Python to pre-cache (system default stays Ubuntu 3.10) |
| `R_VERSION` | latest | Pin a specific R version |
| `RUST_VERSION` | `stable` | Rust toolchain channel |
| `BASE_IMAGE` | `foundation` | Set by docker-cache when reusing monthly `base-deps` |
| `SKIP_BASE_DEPS` | `false` | Set by docker-cache when building incrementally on `base-deps` |

### Quick start

```bash
# Pull the latest base image
docker pull ghcr.io/gwmcelfresh/goodworkflows:latest

# Spin up a quick Python venv
docker run --rm -it ghcr.io/gwmcelfresh/goodworkflows:latest \
  sh -c 'uv venv /tmp/venv && . /tmp/venv/bin/activate && uv pip install pandas && python -c "import pandas; print(pandas.__version__)"'

# Use a newer Python via uv (system default is Ubuntu 3.10)
docker run --rm -it ghcr.io/gwmcelfresh/goodworkflows:latest \
  sh -c 'uv venv --python 3.12 /tmp/venv && . /tmp/venv/bin/activate && python --version'

# Install R packages on the fly
docker run --rm -it ghcr.io/gwmcelfresh/goodworkflows:latest \
  Rscript -e "install.packages('jsonlite', repos='https://cloud.r-project.org'); library(jsonlite); cat('OK\n')"

# Verify uvr is available
docker run --rm -it ghcr.io/gwmcelfresh/goodworkflows:latest \
  uvr --version
```

### Extending the image

```dockerfile
FROM ghcr.io/gwmcelfresh/goodworkflows:latest

# Python deps
RUN uv pip install --system scanpy anndata

# R deps
RUN Rscript -e "install.packages('Seurat', repos='https://cloud.r-project.org')"

# Rust crate (binary)
RUN cargo install ripgrep
```

## License

MIT – see `LICENSE`.
