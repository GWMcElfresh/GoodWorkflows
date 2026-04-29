# Tech Stack

## Core Pipeline

| Technology | Version/Notes | Purpose |
|---|---|---|
| **Nextflow** | ≥24.04, DSL2 | Workflow orchestration, channel-based data flow |
| **Bash** | — | SLURM submission wrappers, repo sync, image pre-pull |
| **R** | Via containers | Seurat object download (Rdiscvr), count export (cellmembrane), metadata tabulation |
| **Python 3** | Via containers | Gene harmonization (mygene, scanpy, anndata), scMODAL training (PyTorch) |

## Container Runtimes

| Runtime | Where Used | Notes |
|---|---|---|
| **Podman** | Local, SLURM (default) | Rootless, `--userns=keep-id` on HPC |
| **Apptainer/Singularity** | HPC (via `slurm_singularity.config`) | SIF pre-pull cache in `${PIPELINE_ROOT}/apptainer-sif/` |
| **Docker** | Local (commented out in local.config) | Alternative to Podman |

## Container Images

| Image | Modules |
|---|---|
| `ghcr.io/bimberlabinternal/rdiscvr:latest` | INGEST, INGEST_METADATA, TABULATE |
| `ghcr.io/bimberlabinternal/cellmembrane:latest` | EXPORT_COUNTS |
| `ghcr.io/gwmcelfresh/scmodal-cuda:latest` | GENE_HARMONIZE, SCMODAL_INTEGRATE |

## HPC Infrastructure

| Component | Details |
|---|---|
| **Scheduler** | SLURM (`sbatch`) |
| **Executor** | `slurm` (Nextflow SLURM executor) |
| **GPU** | NVIDIA (via `--gres=gpu:1 --qos=gpu`) |
| **Filesystem** | NFS scratch (`/gscratch/...`) |
| **Auth** | `.netrc` mounted read-only into containers |

## Documentation & Site

| Tool | Purpose |
|---|---|
| **MkDocs Material** | Static site generation, theme |
| **nf-docs** (`uvx nf-docs generate`) | Auto-generated API reference from Nextflow source |
| **matplotlib** (Python) | Synthetic example plots for docs |
| **GitHub Pages** | Hosting (`gwmcelfresh.github.io/GoodWorkflows/`) |

## CI/CD

| Tool | Purpose |
|---|---|
| **GitHub Actions** | Smoke tests, docs build, docs deploy |
| **`-profile test -stub-run`** | Validates DSL2 wiring without containers or real computation |

## Key Python Libraries (in scmodal-cuda container)

- `torch` — scMODAL model training
- `scanpy` / `anndata` — single-cell data handling
- `mygene` — gene ortholog mapping via HomoloGene
- `scipy` — sparse matrix operations
- `pandas`, `numpy` — data manipulation

## Key R Libraries (in rdiscvr/cellmembrane containers)

- `Rdiscvr` — LabKey/Prime-seq API client
- `Seurat` / `Matrix` — single-cell object I/O
- `dplyr`, `tidyr`, `purrr`, `readr`, `stringr` — tabulation data wrangling