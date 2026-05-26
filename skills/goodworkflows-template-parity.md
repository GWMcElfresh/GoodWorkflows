---
name: goodworkflows-template-parity
description: "Validate and maintain script/config parity between template/gw/ (local GPU) and template/cluster/ (SLURM Apptainer) in GoodWorkflows. Also validates container image list parity across all manifests."
version: 1.0.0
metadata:
  hermes:
    tags: [goodworkflows, nextflow, template, parity, containers, slurm]
---

# GoodWorkflows Template Parity

## Overview

Two template directories must stay functionally synchronized:

| Directory | Purpose | Config Profile | Container Runtime |
|-----------|---------|---------------|-------------------|
| `template/gw/` | Local testing (Bazzite, 32GB RAM / 8GB vRAM) | `local_gpu` | Podman + `--gpus all` + `--privileged` |
| `template/cluster/` | HPC SLURM submissions | `slurm_singularity` | Apptainer SIF from cache |

**Key principle:** Scripts should be functionally equivalent — only config profile, container runtime, image pre-pull strategy, and SLURM-specific params differ.

## What Must Stay in Sync

### 1. Container Image Lists (3 files + 1 source of truth)

| File | What |
|------|------|
| `scripts/image-manifest.txt` | **Source of truth** — one image URI per line |
| `template/gw/setup.sh` — `IMAGES` array | Podman pull list for local setup |
| `scripts/ci/cache_container_images.sh` — `IMAGES` array | Docker pull + save for CI |

All three lists must contain identical image URIs.

### 2. Valid Workflow Lists

| File | What |
|------|------|
| `main.nf` — `supportedWorkflows` | **Source of truth** |
| `template/gw/run.sh` — `VALID_WORKFLOWS` array | Local GPU validation |
| `template/gw/check_workflows.sh` — `WORKFLOW_REGISTRY` | Serial test runner (auto-discovers from main.nf for defaults) |
| `template/cluster/run.sh` — workflow comment block | SLURM documentation |

### 3. NF_ARGS Parity

Core Nextflow arguments identical in both `run.sh` files. Profile-specific args (Podman vs Apptainer, LabKey, SIF cache) are expected to differ.

| Arg | gw/run.sh | cluster/run.sh |
|-----|-----------|----------------|
| `-log` | Yes | Yes |
| `run main.nf` | Yes | Yes |
| `-work-dir` | Yes | Yes |
| `-resume` | Yes | Yes |
| `--workflow` | Yes | Yes |
| `--input` | Yes | Yes |
| `--outdir` | Yes | Yes |
| `-ansi-log false` | No | Yes |
| `-params-file` | No | Yes |
| `--labkey_*` | No | Yes |

## Expected Divergences (Do NOT "Fix")

| Aspect | `template/gw/` | `template/cluster/` |
|--------|----------------|---------------------|
| Profile | `local_gpu` | `slurm_singularity` |
| Container | Podman | Apptainer SIF |
| LabKey creds | Not required | Required |
| SLURM headers | None | `#SBATCH` block |
| Nextflow binary | PATH or `~/bin/` | `NEXTFLOW_BIN` env var |
| Color output | ANSI colors | Plain text |

## Parity Check Procedure

```bash
cd /home/gmcelfresh/GoodWorkflows

# Image list parity
grep -v '^#' scripts/image-manifest.txt | grep -v '^$' | sort
grep -oP '"ghcr\.io/[^"]+"' template/gw/setup.sh | sort
grep -oP '"ghcr\.io/[^"]+"' scripts/ci/cache_container_images.sh | sort

# Workflow list parity
grep -oP "supportedWorkflows\s*=\s*\[.*\]" main.nf
grep "VALID_WORKFLOWS=" template/gw/run.sh

# NF_ARGS parity (shared args)
diff <(grep -oP '^\s+--[\w-]+' template/gw/run.sh | sort) \
     <(grep -oP '^\s+--[\w-]+' template/cluster/run.sh | sort)
```

## Checklist for Adding a New Workflow

- [ ] Add to `main.nf` → `supportedWorkflows`
- [ ] Add container image to `scripts/image-manifest.txt`
- [ ] Add container image to `template/gw/setup.sh` → `IMAGES` array
- [ ] Add container image to `scripts/ci/cache_container_images.sh` → `IMAGES` array
- [ ] Add to `template/gw/run.sh` → `VALID_WORKFLOWS`
- [ ] Add to `template/gw/check_workflows.sh` → WORKFLOW_REGISTRY (if non-default samplesheet)
- [ ] Add to `template/gw/setup.sh` → "Next steps" echo
- [ ] Add to `template/cluster/run.sh` → workflow comment block
- [ ] Add to `template/gw/fetch_example_data.sh` summary "Next: run a workflow"
- [ ] Generate workflow-specific samplesheet in `fetch_example_data.sh`
- [ ] Verify params in `configs/base.config`
- [ ] Verify resources in `configs/local-gpu.config` and `configs/slurm.config`
- [ ] Update Docusaurus docs (`docs/workflows/<name>.md`, `docs/index.md`, `docs/parameters.md`, `docs/usage.md`, `mkdocs.yml`)
- [ ] Audit template for Groovy pitfalls (`$`, `\n`, `\t`)
- [ ] Verify stub-run: `nextflow run main.nf -stub-run -profile test --workflow <name> --input /tmp/test.csv`
- [ ] Add stub output validation to `scripts/ci/run_nextflow_smoke_tests.sh`
- [ ] Add to CI matrix in `.github/workflows/ci.yml`
- [ ] Verify `check_workflows.sh --workflow <name>` passes
- [ ] Run `fetch_example_data.sh` and verify new samplesheet generated

## Known Pitfalls

- **SLURM pre-pull double-quote stripping:** `parse_params_block()` must strip both `"` and `'` quotes.
- **Podman bind mounts require existing host dirs:** `mkdir -p` before `-v` bind.
- **GHCR names use hyphens** (`nmf-vae`), param names use underscores (`nmfvae_container`).
- **Directory is `template/`**, not `templates/`.
- **`workDir` in config overrides CLI `-work-dir`** (Nextflow 26.04) — don't set it in configs when launchers pass `-work-dir` explicitly.
- **`test` profile must include `base.config`** before override config.

## CI/CD Integration Points

- All shell scripts under `template/gw/` and `template/cluster/` must be in CI ShellCheck.
- CI stub-run validates all `.nf` files compile before smoke tests run.
- GPU-era memory specs (8+ GB) inherited from `local-gpu.config` must be overridden in CI profiles to CI-safe levels (4 GB).
- New workflows must be added to CI matrix AND have stub output validation.
