#!/usr/bin/env bash
# slurm_run.sh – Submit the PodmanWrapper pipeline as a SLURM job.
#
# Usage:
#   sbatch slurm_run.sh
#   sbatch --export=ALL,COMPOSE_FILE=my_compose.yaml slurm_run.sh
#
# Environment variables (all optional, have defaults):
#   COMPOSE_FILE     Path to compose file          (default: compose.yaml)
#   PROJECT_NAME     podman-compose project name    (default: job directory name)
#   IMAGE            Container image to run         (default: ghcr.io/gwmcelfresh/podmanwrapper:latest)
#   EXTRA_ARGS       Extra arguments passed to run-compose
# ---------------------------------------------------------------------------- #

# ---------------------------------------------------------------------------- #
# SLURM directives – adjust to match your cluster's partition / QOS names.
# ---------------------------------------------------------------------------- #
#SBATCH --job-name=podman-compose
#SBATCH --output=logs/slurm-%j.out
#SBATCH --error=logs/slurm-%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=02:00:00
# Uncomment and adjust if GPUs are needed:
##SBATCH --gres=gpu:1
# Uncomment to target a specific partition:
##SBATCH --partition=compute
# ---------------------------------------------------------------------------- #

set -euo pipefail

# ---------------------------------------------------------------------------- #
# Configurable defaults
# ---------------------------------------------------------------------------- #
COMPOSE_FILE="${COMPOSE_FILE:-compose.yaml}"
PROJECT_NAME="${PROJECT_NAME:-$(basename "${PWD}")}"
IMAGE="${IMAGE:-ghcr.io/gwmcelfresh/podmanwrapper:latest}"
EXTRA_ARGS="${EXTRA_ARGS:-}"

# ---------------------------------------------------------------------------- #
# Logging
# ---------------------------------------------------------------------------- #
LOG_DIR="${PWD}/logs"
mkdir -p "${LOG_DIR}"

echo "=========================================="
echo " PodmanWrapper SLURM Job"
echo "=========================================="
echo " SLURM_JOB_ID      : ${SLURM_JOB_ID:-local}"
echo " SLURM_NODELIST    : ${SLURM_NODELIST:-local}"
echo " Working directory : ${PWD}"
echo " Compose file      : ${COMPOSE_FILE}"
echo " Project name      : ${PROJECT_NAME}"
echo " Image             : ${IMAGE}"
echo "=========================================="

# ---------------------------------------------------------------------------- #
# Load the podman module if your cluster uses Environment Modules or Lmod.
# Comment out or adjust the module name as needed.
# ---------------------------------------------------------------------------- #
if command -v module &>/dev/null; then
    echo "Loading podman module..."
    module load podman 2>/dev/null || echo "Warning: 'module load podman' failed – continuing anyway"
fi

# ---------------------------------------------------------------------------- #
# Set up XDG_RUNTIME_DIR for rootless Podman.
# SLURM nodes often do not set this automatically.
# ---------------------------------------------------------------------------- #
export XDG_RUNTIME_DIR="${TMPDIR:-/tmp}/runtime-${UID}"
mkdir -p "${XDG_RUNTIME_DIR}"
chmod 0700 "${XDG_RUNTIME_DIR}"
echo "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}"

# ---------------------------------------------------------------------------- #
# Verify Podman is available
# ---------------------------------------------------------------------------- #
if ! command -v podman &>/dev/null; then
    echo "ERROR: podman not found in PATH. Load the module or install podman."
    exit 1
fi
podman --version

# ---------------------------------------------------------------------------- #
# Pull the image (no-op if already cached; avoids repeated network calls)
# ---------------------------------------------------------------------------- #
echo "Pulling image: ${IMAGE}"
podman pull "${IMAGE}" || {
    echo "WARNING: Could not pull ${IMAGE}. Using cached version if available."
}

# ---------------------------------------------------------------------------- #
# Run the pipeline via PodmanWrapper
#
# Mount the current directory as /workspace inside the container.
# The run-compose script is the container's ENTRYPOINT so we just pass args.
#
# Flags used:
#   --rm            remove the container after exit
#   --userns=keep-id  map the host UID/GID into the container (rootless)
#   --security-opt label=disable  relax SELinux labelling on HPC nodes
#   -v $PWD:/workspace  bind-mount the job directory
#   -w /workspace   set the working directory inside the container
#   -e …            pass key environment variables
# ---------------------------------------------------------------------------- #
podman run --rm \
    --userns=keep-id \
    --security-opt label=disable \
    -v "${PWD}":/workspace \
    -w /workspace \
    -e XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}" \
    -e SLURM_JOB_ID="${SLURM_JOB_ID:-}" \
    -e SLURM_NODELIST="${SLURM_NODELIST:-}" \
    -e SLURM_NTASKS="${SLURM_NTASKS:-}" \
    -e SLURM_CPUS_ON_NODE="${SLURM_CPUS_ON_NODE:-}" \
    -e TMPDIR="${TMPDIR:-/tmp}" \
    "${IMAGE}" \
    --file         "${COMPOSE_FILE}" \
    --project-name "${PROJECT_NAME}" \
    --workdir      /workspace \
    --log-dir      /workspace/logs \
    --down \
    ${EXTRA_ARGS}

echo "=========================================="
echo " Job finished: $(date)"
echo "=========================================="
