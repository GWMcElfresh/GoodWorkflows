#!/usr/bin/env bash
# Submit the GoodWorkflows Nextflow orchestrator to SLURM.
#
# Usage:
#   sbatch slurm_nextflow.sh
#   sbatch slurm_nextflow.sh --workflow ingest_export
#   sbatch --export=ALL,NXF_WORK=/gscratch/lab/work slurm_nextflow.sh
#   sbatch --export=ALL,SYNC_REPO_BEFORE_RUN=true slurm_nextflow.sh
#
# Recommended HPC pattern:
#   1) sync the checkout with: sbatch slurm_sync_repo.sh
#   2) launch the pipeline with this script

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

NEXTFLOW_BIN="${NEXTFLOW_BIN:-/gscratch/CHANGEME/nextflow}"
export NXF_HOME="${NXF_HOME:-/gscratch/CHANGEME/.nextflow}"

LOG_DIR="${PWD}/logs"
mkdir -p "${LOG_DIR}"

NXF_WORK_DISPLAY="${NXF_WORK:-${PWD}/work}"
SYNC_SCRIPT_PATH="${SYNC_SCRIPT:-${PWD}/scripts/sync_repo.sh}"

echo "=========================================="
echo " GoodWorkflows Nextflow Orchestrator"
echo "=========================================="
echo " SLURM_JOB_ID   : ${SLURM_JOB_ID:-local}"
echo " SLURM_NODELIST : ${SLURM_NODELIST:-local}"
echo " Working dir    : ${PWD}"
echo " Nextflow bin   : ${NEXTFLOW_BIN}"
echo " NXF_HOME       : ${NXF_HOME}"
echo " NXF_WORK       : ${NXF_WORK_DISPLAY}"
echo " Podman cache   : ${NXF_PODMAN_CACHEDIR:-not set}"
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
    run main.nf
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
