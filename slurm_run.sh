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
# SLURM directives
# ---------------------------------------------------------------------------- #
#SBATCH --job-name=podman-compose
#SBATCH --ntasks=1
#SBATCH --get-user-env
#SBATCH --output=logs/slurm-%j.out
#SBATCH --error=logs/slurm-%j.err
#SBATCH --cpus-per-task=4
#NOTE: update this to change RAM (in MB)
#SBATCH --mem=16000
#SBATCH --partition=batch
#SBATCH --time=0-02:00
# Uncomment and adjust if GPUs are needed:
##SBATCH --gres=gpu:1
# ---------------------------------------------------------------------------- #

set -euo pipefail

# ---------------------------------------------------------------------------- #
# Configurable defaults
# ---------------------------------------------------------------------------- #
COMPOSE_FILE="${COMPOSE_FILE:-compose.yaml}"
PROJECT_NAME="${PROJECT_NAME:-$(basename "${PWD}")}"
IMAGE="${IMAGE:-ghcr.io/gwmcelfresh/podmanwrapper:latest}"
EXTRA_ARGS="${EXTRA_ARGS:-}"
USER="${USER:-$(id -un)}"

OVERWRITE=0

# ---------------------------------------------------------------------------- #
# PATH – ensure local bin is available
# ---------------------------------------------------------------------------- #
export PATH=$PATH:/home/users/${USER}/.local/bin


# ---------------------------------------------------------------------------- #
# Parse flags
# ---------------------------------------------------------------------------- #
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --overwrite) OVERWRITE=1 ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

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
# Verify Podman is available
# ---------------------------------------------------------------------------- #
if ! command -v podman &>/dev/null; then
    echo "ERROR: podman not found in PATH. Load the module or install podman."
    exit 1
fi
podman --version

# ---------------------------------------------------------------------------- #
# Redirect Podman storage to local node scratch ($TMPDIR).
#
# By default Podman resolves storage from $HOME, which on this cluster points
# to a network filesystem (gscratch/NFS/Lustre).  Those filesystems do not
# support overlayfs mounts, causing:
#   "crun: open .../merged: Permission denied: OCI permission denied"
# Pointing graph/run roots at $TMPDIR (local SSD/RAM on the compute node)
# avoids the NFS restriction and also sidesteps "database driver mismatch"
# errors from any stale overlay database left in the home directory.
# ---------------------------------------------------------------------------- #
LOCAL_PODMAN_ROOT="${TMPDIR:-/tmp}/podman-${SLURM_JOB_ID:-$$}"
export CONTAINERS_GRAPHROOT="${LOCAL_PODMAN_ROOT}/storage"
export CONTAINERS_RUNROOT="${LOCAL_PODMAN_ROOT}/run"
mkdir -p "${CONTAINERS_GRAPHROOT}" "${CONTAINERS_RUNROOT}"
echo "CONTAINERS_GRAPHROOT=${CONTAINERS_GRAPHROOT}"
echo "CONTAINERS_RUNROOT=${CONTAINERS_RUNROOT}"

# ---------------------------------------------------------------------------- #
# Set up XDG_RUNTIME_DIR for rootless Podman.
# SLURM nodes often do not set this automatically.
# ---------------------------------------------------------------------------- #
export XDG_RUNTIME_DIR="${TMPDIR:-/tmp}/runtime-${UID}"
mkdir -p "${XDG_RUNTIME_DIR}"
chmod 0700 "${XDG_RUNTIME_DIR}"
echo "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}"

# ---------------------------------------------------------------------------- #
# Pull the image (respects --overwrite flag)
# ---------------------------------------------------------------------------- #
if [[ $OVERWRITE -eq 1 ]]; then
    echo "Forcing re-pull of image: ${IMAGE}"
    podman rmi "${IMAGE}" 2>/dev/null || true
    podman pull "${IMAGE}"
else
    if ! podman image exists "${IMAGE}" 2>/dev/null; then
        echo "Image not cached, pulling: ${IMAGE}"
        podman pull "${IMAGE}"
    else
        echo "Using cached image: ${IMAGE}"
    fi
fi

# ---------------------------------------------------------------------------- #
# Run the pipeline via PodmanWrapper
#
# Mount the current directory as /workspace inside the container.
# The run-compose script is the container's ENTRYPOINT so we just pass args.
#
# Flags used:
#   --rm                   remove the container after exit
#   --userns=keep-id       map the host UID/GID into the container (rootless)
#   --group-add keep-groups  preserve all supplemental group memberships so the
#                          container process can access gscratch, RDS, and other
#                          shared filesystems that are gated by secondary groups.
#                          Without this, rootless Podman drops to only UID + GID,
#                          which will cause EPERM on group-restricted paths.
#   --security-opt label=disable  relax SELinux labelling on HPC nodes
#   -v $PWD:/workspace     bind-mount the job directory
#   -w /workspace          set the working directory inside the container
#   -e …                   pass key environment variables
# ---------------------------------------------------------------------------- #
podman run --rm \
    --userns=keep-id \
    --group-add keep-groups \
    --security-opt label=disable \
    -v "${PWD}":/workspace \
    -w /workspace \
    -e XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}" \
    -e SLURM_JOB_ID="${SLURM_JOB_ID:-}" \
    -e SLURM_NODELIST="${SLURM_NODELIST:-}" \
    -e SLURM_NTASKS="${SLURM_NTASKS:-}" \
    -e SLURM_CPUS_ON_NODE="${SLURM_CPUS_ON_NODE:-}" \
    -e TMPDIR=/tmp \
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
