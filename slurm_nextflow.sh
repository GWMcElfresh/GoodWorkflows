#!/usr/bin/env bash
# Submit the GoodWorkflows Nextflow orchestrator to SLURM.
#
# Usage:
#   sbatch slurm_nextflow.sh
#   sbatch slurm_nextflow.sh --workflow integration
#   bash slurm_nextflow.sh --workflow ingest_tabulate   # submits pre-pull + orchestrator dependency chain
#   sbatch --export=ALL,NXF_WORK=/gscratch/lab/work slurm_nextflow.sh
#   sbatch --export=ALL,SYNC_REPO_BEFORE_RUN=true slurm_nextflow.sh
#
# Tip: this script can be submitted from any working directory because
# PIPELINE_ROOT is resolved from the script file's own location.

#SBATCH --job-name=nf-orchestrator
#SBATCH --ntasks=1
#SBATCH --get-user-env
#SBATCH --cpus-per-task=8
#SBATCH --mem=32000
#SBATCH --partition=batch
#SBATCH --time=1-00:00
#SBATCH --output=logs/slurm-orchestrator-%j.out
#SBATCH --error=logs/slurm-orchestrator-%j.err

set -euo pipefail

# Resolve pipeline root from this script's own location so the script can be
# submitted from any working directory (e.g. runs/my_run/).
PIPELINE_ROOT="${PIPELINE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
PREPULL_SCRIPT_PATH="${PREPULL_SCRIPT:-${PIPELINE_ROOT}/scripts/slurm_prepull_images.sh}"

# Submit mode: when invoked directly (not already inside a SLURM allocation),
# submit a serial pre-pull job and chain the orchestrator with dependency.
if [[ -z "${SLURM_JOB_ID:-}" && "${AUTO_SUBMIT_WITH_PREPULL:-true}" == "true" ]]; then
    if ! command -v sbatch >/dev/null 2>&1; then
        echo "ERROR: sbatch not found. Either run this script with sbatch, or install/load SLURM client tools."
        exit 1
    fi
    if [[ ! -f "${PREPULL_SCRIPT_PATH}" ]]; then
        echo "ERROR: pre-pull script not found: ${PREPULL_SCRIPT_PATH}"
        exit 1
    fi

    PREPULL_JOB_ID="$(sbatch --parsable "${PREPULL_SCRIPT_PATH}" "$@")"
    ORCHESTRATOR_JOB_ID="$(sbatch --parsable --dependency=afterok:${PREPULL_JOB_ID} --export=ALL,INLINE_PREPULL_WHEN_SBATCH=false "${PIPELINE_ROOT}/slurm_nextflow.sh" "$@")"

    echo "Submitted pre-pull job     : ${PREPULL_JOB_ID}"
    echo "Submitted orchestrator job : ${ORCHESTRATOR_JOB_ID} (afterok:${PREPULL_JOB_ID})"
    exit 0
fi

# Inline fallback: if users still submit this script directly via sbatch,
# run pre-pull in the same allocation before launching Nextflow.
if [[ -n "${SLURM_JOB_ID:-}" && "${INLINE_PREPULL_WHEN_SBATCH:-true}" == "true" ]]; then
    if [[ -f "${PREPULL_SCRIPT_PATH}" ]]; then
        echo "Running inline pre-pull before Nextflow launch..."
        bash "${PREPULL_SCRIPT_PATH}" "$@"
    else
        echo "WARNING: Pre-pull script not found at ${PREPULL_SCRIPT_PATH}; continuing without inline pre-pull."
    fi
fi

NEXTFLOW_BIN="${NEXTFLOW_BIN:-/gscratch/CHANGEME/nextflow}"
export NXF_HOME="${NXF_HOME:-/gscratch/CHANGEME/.nextflow}"

NXF_WORK_ROOT="${NXF_WORK:-${PWD}/work}"

# Rootless podman may unpack multi-GB image layers. Prefer SLURM job-local tmp
# when available, otherwise fall back to NXF_WORK-backed scratch.
export NXF_PODMAN_TMPDIR="${NXF_PODMAN_TMPDIR:-${SLURM_TMPDIR:-${NXF_WORK_ROOT}/.podman-tmp}}"
# Shared image store that survives the pre-pull job and is mounted read-only by
# task-local podman storage via additionalimagestores.
export NXF_PODMAN_CACHEDIR="${NXF_PODMAN_CACHEDIR:-${NXF_WORK_ROOT}/.podman-cache}"
# Shared lock path to coordinate container pulls across concurrent tasks/jobs.
export NXF_PODMAN_PULL_LOCK_DIR="${NXF_PODMAN_PULL_LOCK_DIR:-${NXF_WORK_ROOT}/.podman-pull-locks}"

mkdir -p "${NXF_PODMAN_TMPDIR}" "${NXF_PODMAN_CACHEDIR}" "${NXF_PODMAN_PULL_LOCK_DIR}"

LOG_DIR="${PWD}/logs"
mkdir -p "${LOG_DIR}"

NXF_WORK_DISPLAY="${NXF_WORK_ROOT}"
SYNC_SCRIPT_PATH="${SYNC_SCRIPT:-${PIPELINE_ROOT}/scripts/sync_repo.sh}"

echo "=========================================="
echo " GoodWorkflows Nextflow Orchestrator"
echo "=========================================="
echo " SLURM_JOB_ID   : ${SLURM_JOB_ID:-local}"
echo " SLURM_NODELIST : ${SLURM_NODELIST:-local}"
echo " Working dir    : ${PWD}"
echo " Pipeline root  : ${PIPELINE_ROOT}"
echo " Nextflow bin   : ${NEXTFLOW_BIN}"
echo " NXF_HOME       : ${NXF_HOME}"
echo " NXF_WORK       : ${NXF_WORK_DISPLAY}"
echo " Podman tmp dir : ${NXF_PODMAN_TMPDIR}"
echo " Pull lock dir  : ${NXF_PODMAN_PULL_LOCK_DIR}"
echo " Podman cache   : ${NXF_PODMAN_CACHEDIR:-not set}"
echo " Podman tmp free:"
df -h "${NXF_PODMAN_TMPDIR}" || true
echo " Podman tmp inodes:"
df -i "${NXF_PODMAN_TMPDIR}" || true
echo "=========================================="

USER="${USER:-$(id -un)}"
export PATH="${PATH}:/home/users/${USER}/.local/bin"

if [[ ! -x "${NEXTFLOW_BIN}" ]]; then
    echo "ERROR: Nextflow binary not found or not executable: ${NEXTFLOW_BIN}"
    echo "Set NEXTFLOW_BIN to your nextflow installation path."
    exit 1
fi

if [[ "${SYNC_REPO_BEFORE_RUN:-false}" == "true" ]]; then
    echo "Sync requested before launch: ${SYNC_SCRIPT_PATH}"
    bash "${SYNC_SCRIPT_PATH}" "${PWD}"
fi

"${NEXTFLOW_BIN}" -version

declare -a NF_ARGS
NF_ARGS=(
    -log "${LOG_DIR}/nextflow.log"
    run "${PIPELINE_ROOT}/main.nf"
    -profile slurm
    -resume
    -ansi-log false
)

if [[ -n "${NXF_PARAMS_FILE:-}" && -f "${NXF_PARAMS_FILE}" ]]; then
    NF_ARGS+=( -params-file "${NXF_PARAMS_FILE}" )
fi

NF_ARGS+=( "$@" )

echo "Launching: ${NEXTFLOW_BIN} ${NF_ARGS[*]}"
"${NEXTFLOW_BIN}" "${NF_ARGS[@]}"

echo "=========================================="
echo " Nextflow finished: $(date)"
echo "=========================================="
