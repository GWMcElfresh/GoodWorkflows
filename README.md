# GoodWorkflows

A DSL2 **Nextflow** repository for composing reusable single-cell workflows from small modules and running them on **SLURM + Podman** HPC systems.

---

## Repository layout

```text
.
├── main.nf                 # Thin launcher for saved workflows
├── workflows/              # Higher-level reusable workflows
├── modules/local/          # Single-step DSL2 modules
├── configs/                # Base + profile-specific config
├── data/                   # Default repo-local input location
├── outputs/                # Default published results (generated)
├── work/                   # Nextflow work dir (generated)
├── logs/                   # Reports and SLURM logs (generated)
├── slurm_nextflow.sh       # Run the pipeline on HPC
└── slurm_sync_repo.sh      # Fast clone / update job for HPC checkouts
```

## Saved workflows

| Workflow | Purpose |
|---|---|
| `full` | `INGEST -> EXPORT_COUNTS -> GENE_HARMONIZE -> SCMODAL_INTEGRATE` |
| `ingest_export` | Download Seurat objects and export 10x-like counts only |

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

```bash
nextflow run main.nf -profile local \
  --workflow full \
  --labkey_base_url https://labkey.example.org \
  --labkey_folder /My/Folder
```

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

### 2. Launch the pipeline

```bash
sbatch slurm_nextflow.sh \
  --workflow full \
  --labkey_base_url https://labkey.example.org \
  --labkey_folder /My/Folder
```

Optional: fast-forward the checkout immediately before launch:

```bash
sbatch --export=ALL,SYNC_REPO_BEFORE_RUN=true slurm_nextflow.sh --workflow full
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
3. launch `slurm_nextflow.sh`

---

## CI testing strategy

GitHub Actions now validates the repository in two layers:

1. **Workflow smoke tests** — runs `main.nf` with `-profile test -stub-run` for both `full` and `ingest_export`
2. **Module smoke tests** — runs each module wrapper under `tests/modules/` so every module is exercised independently

The `test` profile disables containers and uses the local executor so CI can validate DSL2 wiring quickly without requiring HPC infrastructure.

For container-dependent validation, the repo also includes `scripts/ci/cache_container_images.sh`, which can pre-pull and cache the module images into `.ci/docker-cache/` during GitHub Actions runs.

## License

MIT – see `LICENSE`.
