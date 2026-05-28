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
| `ghcr.io/bimberlabinternal/rdiscvr:latest` | INGEST_LABKEY, INGEST_URL, INGEST_FILE, INGEST_METADATA, TABULATE |
| `ghcr.io/bimberlabinternal/cellmembrane:latest` | EXPORT_COUNTS |
| `ghcr.io/gwmcelfresh/scmodal:latest` | GENE_HARMONIZE, SCMODAL_INTEGRATE |
| `ghcr.io/gwmcelfresh/goodworkflows:latest` | `batch_effect_assessments` metric processes (on-the-fly **uvr** R deps) |

### GoodWorkflows base image (non-module)

| Image | Runtimes | Package managers | Purpose |
|---|---|---|---|
| `ghcr.io/gwmcelfresh/goodworkflows:latest` | Python 3.10 (system) + uv-managed 3.12, R, Rust | [`uv`](https://github.com/astral-sh/uv), [`uvr`](https://github.com/nbafrank/uvr) | Shared base for ad-hoc Python/R deps, prototyping, and `FROM` extension |

Built from repo `Dockerfile` (`foundation` → `deps` → `runtime`); published by `.github/workflows/docker-publish.yml` via [dockerDependencies](https://github.com/GWMcElfresh/dockerDependencies). Module images above remain the default Nextflow runtimes for existing workflows.

**Ad-hoc dependency patterns:**

- Python: `uv pip install --system <pkg>` on system 3.10, or `uv python install 3.12` + `uv venv --python 3.12`
- R: `uvr init`, `uvr add <pkg>`, `uvr sync`, `uvr run script.R`; CI reproducibility via `uvr sync --frozen`

**EV-002 (`batch_effect_assessments`):** each assessment task runs `uvr init` in `${PWD}/.uvr-workspace`, installs scIntegrationMetrics/kBET, `uvr run -- Rscript …`, then removes the workspace on exit.

## HPC Infrastructure

| Component | Details |
|---|---|
| **Scheduler** | SLURM (`sbatch`) |
| **Executor** | `slurm` (Nextflow SLURM executor) |
| **GPU** | NVIDIA (via `--gres=gpu:1 --qos=gpu`) |
| **Filesystem** | NFS scratch (`/gscratch/...`) |
| **Auth** | `.netrc` mounted read-only into containers (LabKey-mode ingest only) |

## MCP Server (`mcp-server/`)

| Technology | Version/Notes | Purpose |
|---|---|---|
| **TypeScript** | Node.js 20 | Model Context Protocol server for LLM/agent tooling |
| **npm** | `package-lock.json` in `mcp-server/` | Dependency management |
| **Python** (`requirements.txt`) | pytest, mcp | Python test harness for MCP server integration tests |

The MCP server exposes pipeline tools (samplesheet analysis, workflow suggestion, composition) for use by AI coding agents. Tests run in the `test-mcp.yml` GitHub Actions workflow.

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

## Key Python Libraries (in scmodal container)

- `torch` — scMODAL model training
- `scanpy` / `anndata` — single-cell data handling
- `mygene` — gene ortholog mapping via HomoloGene
- `scipy` — sparse matrix operations
- `pandas`, `numpy` — data manipulation

## Key R Libraries (in rdiscvr/cellmembrane containers)

- `Rdiscvr` — LabKey/Prime-seq API client
- `Seurat` / `Matrix` — single-cell object I/O
- `dplyr`, `tidyr`, `purrr`, `readr`, `stringr` — tabulation data wrangling