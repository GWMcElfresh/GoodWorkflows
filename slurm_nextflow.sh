#!/usr/bin/env bash
# slurm_nextflow.sh – Submit the Nextflow orchestrator to SLURM.
#
# This job runs Nextflow itself; Nextflow in turn submits each pipeline process
# as its own SLURM job.  The orchestrator node needs enough RAM and wall-time
# to manage the full run but does NOT need a GPU.
#
# Usage:
#   sbatch slurm_nextflow.sh                          # use defaults
#   sbatch slurm_nextflow.sh --input my_samples.csv   # pass params to Nextflow
#   sbatch --export=ALL,NXF_WORK=/gscratch/lab/work slurm_nextflow.sh
#
# Key environment variables (export before sbatch):
#   NEXTFLOW_BIN        Path to the nextflow executable
#                       Default: /gscratch/CHANGEME/nextflow
#   NXF_HOME            Nextflow's own cache/plugin directory
#                       Default: /gscratch/CHANGEME/.nextflow
#   NXF_WORK            Nextflow work directory (must be on shared FS)
#                       Default: ./work  (relative to sbatch launch directory)
#   NXF_PODMAN_CACHEDIR Path to an existing Podman image store on gscratch.
#                       When set, tasks read pre-pulled images from this store
#                       instead of pulling from GHCR every time.
#                       Example population command (run once per image):
#                         CONTAINERS_GRAPHROOT=$NXF_PODMAN_CACHEDIR \
#                           podman pull ghcr.io/bimberlabinternal/rdiscvr:latest
#   NXF_PODMAN_VOLUMES  Extra "-v src:dst" mounts for all containers, e.g.:
#                         export NXF_PODMAN_VOLUMES="-v /gscratch/lab:/gscratch/lab"
#   NXF_PARAMS_FILE     Path to a YAML/JSON params file (--params-file)
# ---------------------------------------------------------------------------- #

# ---------------------------------------------------------------------------- #
# SLURM directives
# ---------------------------------------------------------------------------- #
#SBATCH --job-name=nf-orchestrator
#SBATCH --ntasks=1
#SBATCH --get-user-env
#SBATCH --cpus-per-task=8
#NOTE: update --mem for larger runs; orchestrator RAM is for Nextflow JVM + bookkeeping
#SBATCH --mem=32000
#SBATCH --partition=batch
#SBATCH --time=1-00:00
#SBATCH --output=logs/slurm-orchestrator-%j.out
#SBATCH --error=logs/slurm-orchestrator-%j.err
# ---------------------------------------------------------------------------- #

set -euo pipefail

# ---------------------------------------------------------------------------- #
# Configurable paths – override by exporting before sbatch
# ---------------------------------------------------------------------------- #
NEXTFLOW_BIN="${NEXTFLOW_BIN:-/gscratch/CHANGEME/nextflow}"
export NXF_HOME="${NXF_HOME:-/gscratch/CHANGEME/.nextflow}"

# ---------------------------------------------------------------------------- #
# Logging setup
# ---------------------------------------------------------------------------- #
LOG_DIR="${PWD}/logs"
mkdir -p "${LOG_DIR}"

echo "=========================================="
echo " Nextflow SLURM Orchestrator"
echo "=========================================="
echo " SLURM_JOB_ID   : ${SLURM_JOB_ID:-local}"
echo " SLURM_NODELIST : ${SLURM_NODELIST:-local}"
echo " Working dir    : ${PWD}"
echo " Nextflow bin   : ${NEXTFLOW_BIN}"
echo " NXF_HOME       : ${NXF_HOME}"
echo " NXF_WORK       : ${NXF_WORK:-./work (default)}"
echo " Podman cache   : ${NXF_PODMAN_CACHEDIR:-(not set, images pulled on demand)}"
echo "=========================================="

# ---------------------------------------------------------------------------- #
# PATH – expose Nextflow and any local user bin
# ---------------------------------------------------------------------------- #
USER="${USER:-$(id -un)}"
export PATH="${PATH}:/home/users/${USER}/.local/bin"

# ---------------------------------------------------------------------------- #
# Java – Nextflow bundles a JRE since v23; uncomment if your installation
# uses an external Java and the cluster requires a module load.
# ---------------------------------------------------------------------------- #
# if command -v module &>/dev/null; then
#     module load java/17 2>/dev/null || echo "Warning: 'module load java' failed"
# fi

# ---------------------------------------------------------------------------- #
# Verify Nextflow is available
# ---------------------------------------------------------------------------- #
if [[ ! -x "${NEXTFLOW_BIN}" ]]; then
    echo "ERROR: Nextflow binary not found or not executable: ${NEXTFLOW_BIN}"
    echo "       Set NEXTFLOW_BIN to your nextflow installation path."
    exit 1
fi
"${NEXTFLOW_BIN}" -version

# ---------------------------------------------------------------------------- #
# Build Nextflow invocation
# ---------------------------------------------------------------------------- #
NF_ARGS=(
    -log  "${LOG_DIR}/nextflow.log"
    run   main.nf
    -resume                          # enable checkpointing / automatic restart
    -ansi-log false                  # cleaner output in SLURM log files
)

# Append --params-file if provided
if [[ -n "${NXF_PARAMS_FILE:-}" && -f "${NXF_PARAMS_FILE}" ]]; then
    NF_ARGS+=( -params-file "${NXF_PARAMS_FILE}" )
fi

# Pass any additional arguments (e.g. --input my_samples.csv --outdir results)
# supplied after the script name when calling sbatch:
#   sbatch slurm_nextflow.sh --input custom.csv
NF_ARGS+=( "$@" )

# ---------------------------------------------------------------------------- #
# Run Nextflow
# ---------------------------------------------------------------------------- #
echo "Launching: ${NEXTFLOW_BIN} ${NF_ARGS[*]}"
"${NEXTFLOW_BIN}" "${NF_ARGS[@]}"

echo "=========================================="
echo " Nextflow finished: $(date)"
echo "=========================================="
