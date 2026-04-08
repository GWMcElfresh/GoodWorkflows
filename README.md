# PodmanWrapper

A lightweight wrapper around **podman-compose** for running multi-container workflows inside a **SLURM** job on an HPC cluster.

## Overview

PodmanWrapper packages `podman-compose` inside a container image and provides a robust CLI entrypoint (`run-compose`) that:

* Sets up a rootless Podman environment automatically
* Detects SLURM environment variables and configures scratch / runtime directories accordingly
* Runs a `compose.yaml` pipeline with a single `podman run` command from your SLURM job script
* Captures logs per run and supports optional cleanup (`--down`)

### Why this instead of multi-job workflows?

| Concern | Multi-job (SLURM arrays) | PodmanWrapper (single job) |
|---|---|---|
| Orchestration complexity | High | Low |
| Cross-node networking | Supported | **Not supported** |
| Shared filesystem required | Yes | No (named volumes) |
| Reproducibility | Medium | High (single image) |
| Startup overhead | High | Low |

Use PodmanWrapper when your pipeline fits on **one node** and you want the simplicity of Docker Compose semantics without Kubernetes.

---

## Repository Structure

```
.
├── Dockerfile              # Container image (Rocky Linux 9 + rootless Podman)
├── run-compose             # Entrypoint / CLI wrapper script
├── compose.yaml            # Example 3-stage pipeline
├── slurm_run.sh            # Example SLURM job script
├── .env.example            # Template for environment overrides
├── workspace/              # Bind-mounted into all compose services
├── .github/
│   └── workflows/
│       └── ci.yml          # Lint → Build → Push → Integration test
└── README.md
```

---

## Quick Start

### 1. Build the image

```bash
docker build -t podmanwrapper:local .
# or
podman build -t podmanwrapper:local .
```

### 2. Pull the published image

```bash
podman pull ghcr.io/gwmcelfresh/podmanwrapper:latest
```

### 3. Run locally with Podman

```bash
# Dry-run (prints commands without executing)
podman run --rm \
  --userns=keep-id \
  -v "$PWD":/workspace \
  -w /workspace \
  ghcr.io/gwmcelfresh/podmanwrapper:latest \
  --file compose.yaml \
  --dry-run

# Live run with cleanup
podman run --rm \
  --userns=keep-id \
  -v "$PWD":/workspace \
  -w /workspace \
  ghcr.io/gwmcelfresh/podmanwrapper:latest \
  --file compose.yaml \
  --project-name mypipeline \
  --down
```

### 4. Submit to SLURM

```bash
# Copy and customise the environment file
cp .env.example .env

# Submit
sbatch slurm_run.sh
```

Monitor job output:
```bash
tail -f logs/slurm-<JOBID>.out
```

---

## `run-compose` CLI Reference

```
Usage: run-compose [OPTIONS]

Options:
  -f, --file FILE          Compose file to use          (default: compose.yaml)
  -p, --project-name NAME  Project name                 (default: basename of workdir)
  -w, --workdir DIR        Working directory             (default: $PWD)
  -e, --env-file FILE      Optional .env file to load
  -l, --log-dir DIR        Log directory                 (default: <workdir>/logs)
  -d, --down               Run 'podman-compose down' after workflow exits
  -n, --dry-run            Print commands; do not execute
  -h, --help               Show this help and exit
```

Logs are written to `<log-dir>/<project>-<timestamp>/compose.log`.

---

## SLURM Script Reference (`slurm_run.sh`)

Key parameters you can override via `sbatch --export` or by editing the script:

| Variable | Default | Description |
|---|---|---|
| `COMPOSE_FILE` | `compose.yaml` | Compose file path |
| `PROJECT_NAME` | `basename $PWD` | Podman-compose project name |
| `IMAGE` | `ghcr.io/gwmcelfresh/podmanwrapper:latest` | Container image |
| `EXTRA_ARGS` | _(empty)_ | Extra flags passed to `run-compose` |

GPU jobs: uncomment `#SBATCH --gres=gpu:1` and add `--device nvidia.com/gpu=all` to the `podman run` command.

---

## Example Compose Pipeline

The bundled `compose.yaml` defines three services that run sequentially:

```
preprocess → model → postprocess
```

All three share a named `data` volume — no external network is required.

| Stage | Reads from | Writes to |
|---|---|---|
| `preprocess` | `/data/input` | `/data/interim` |
| `model` | `/data/interim` | `/data/output` |
| `postprocess` | `/data/output` | `/data/results` |

To add real input data, place files in `workspace/` or map a host directory to `/data/input` via an extra `-v` flag:

```yaml
services:
  preprocess:
    volumes:
      - /scratch/myproject/raw:/data/input:ro
      - data:/data
```

---

## Rootless Podman – Assumptions

1. **Host subuid/subgid mapping** – the cluster administrator must add entries for each user in `/etc/subuid` and `/etc/subgid`.  A typical entry looks like:
   ```
   alice:100000:65536
   ```
2. **`fuse-overlayfs`** – used as the storage driver inside the container when the kernel does not support native overlay in user namespaces.
3. **`XDG_RUNTIME_DIR`** – must be a writable directory owned by the running user.  `slurm_run.sh` sets this automatically using `$TMPDIR` (SLURM local scratch) or `/tmp/runtime-<UID>`.
4. **No root privileges required** – `podman run --userns=keep-id` maps the host UID into the container transparently.

---

## Limitations

* **Single node only** – services share a named volume which lives on one node's filesystem.
* **No cross-node networking** – CNI / Netavark is not configured for multi-host mode.
* **Air-gapped clusters** – pre-pull the image with `podman save / load` or mirror to a local registry.
* **Storage driver** – `fuse-overlayfs` requires the `fuse` kernel module.  Some very locked-down clusters may need `--storage-driver=vfs` (slower).

---

## CI/CD

The GitHub Actions workflow (`.github/workflows/ci.yml`) performs:

1. **Lint** – Hadolint (Dockerfile), ShellCheck (`run-compose`, `slurm_run.sh`), `docker compose config`
2. **Build & Push** – multi-platform image pushed to `ghcr.io/gwmcelfresh/podmanwrapper` on every push to `main`
3. **Integration Test** – runs the full `compose.yaml` pipeline using `podman-compose` on the CI runner

Image tags:
* `latest` – tip of `main`
* `sha-<short-sha>` – every commit
* `<branch>` – branch builds
* `<semver>` – on tagged releases

---

## License

MIT – see [LICENSE](LICENSE).