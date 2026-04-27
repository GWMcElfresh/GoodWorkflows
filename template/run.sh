#!/usr/bin/env bash
# Per-run Nextflow launcher template for GoodWorkflows.
#
# USAGE
#   1. Copy the template/ directory into runs/<my_run_name>/
#        cp -r /path/to/GoodWorkflows/template runs/my_run
#   2. Edit the samplesheet.csv: one row per sample.
#   3. Fill in the FILL IN section below.
#   4. Submit on SLURM:  sbatch run.sh
#      This template performs an inline container image pre-pull in the same
#      SLURM allocation before launching Nextflow.
#   5. Or run locally:  bash run.sh   # CPU workflows only; no SLURM pre-pull
#
# Alternative SLURM entrypoint:
#   If you want the pre-pull to run as a separate SLURM job before the
#   orchestrator starts, launch from the repository root with:
#       bash slurm_nextflow.sh --workflow <name> ...
#
# All outputs land in:
#   runs/<my_run_name>/outputs/   (results)
#   runs/<my_run_name>/work/      (nextflow intermediate files)
#   runs/<my_run_name>/logs/      (nextflow and SLURM logs)
#
# The run directory is gitignored, so nothing here is committed.

#SBATCH --job-name=nf-run
#SBATCH --ntasks=1
#SBATCH --get-user-env
#SBATCH --cpus-per-task=2
#SBATCH --mem=32000
#SBATCH --partition=batch
#SBATCH --time=1-00:00
#SBATCH --gres=disk:1028
#SBATCH --output=logs/slurm-%j.out
#SBATCH --error=logs/slurm-%j.err

set -euo pipefail

# ============================================================
# FILL IN — required settings
# ============================================================

# Named workflow to run. Choose one:
#   integration    Full pipeline: ingest -> export -> harmonize -> scMODAL  (GPU/HPC required)
#   ingest_export  Download Seurat objects and export 10x-like counts        (CPU, local or HPC)
#   ingest_tabulate  Download metadata and build subjectIdTable.csv          (CPU, local or HPC)
WORKFLOW="ingest_tabulate"

# LabKey / Prime-seq server credentials (also requires ~/.netrc for authentication)
LABKEY_BASE_URL="https://labkey.example.org" #for OHSU, use https://prime-seq.ohsu.edu
LABKEY_FOLDER="/My/Project/Folder" #for Bimber use /Labs/Bimber

# Path to the Nextflow binary on this cluster
NEXTFLOW_BIN="${NEXTFLOW_BIN:-/gscratch/CHANGEME/nextflow}"

# Nextflow home directory (plugin/cache storage)
export NXF_HOME="${NXF_HOME:-/gscratch/CHANGEME/.nextflow}"

# ============================================================
# Auto-detect PIPELINE_ROOT
# ============================================================
# Walk up from the current directory looking for main.nf (the pipeline root).
# Override by setting PIPELINE_ROOT in the environment before calling sbatch.

if [[ -z "${PIPELINE_ROOT:-}" ]]; then
    # Under SLURM, BASH_SOURCE[0] may point to the spool copy of the script,
    # not the original path. SLURM_SUBMIT_DIR is always the directory sbatch
    # was invoked from, which is the reliable starting point.
    if [[ -n "${SLURM_JOB_ID:-}" && -n "${SLURM_SUBMIT_DIR:-}" ]]; then
        _search_dir="${SLURM_SUBMIT_DIR}"
    else
        _search_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    fi
    _found=""
    for _i in 1 2 3 4 5; do
        if [[ -f "${_search_dir}/main.nf" ]]; then
            _found="${_search_dir}"
            break
        fi
        _search_dir="$(dirname "${_search_dir}")"
    done
    if [[ -z "${_found}" ]]; then
        echo "ERROR: Could not locate main.nf within 5 parent directories of this script."
        echo "Set PIPELINE_ROOT explicitly:  PIPELINE_ROOT=/path/to/GoodWorkflows sbatch run.sh"
        exit 1
    fi
    PIPELINE_ROOT="${_found}"
fi

# ============================================================
# Per-run paths (all relative to PWD = the run directory)
# ============================================================
RUN_DIR="${PWD}"
INPUT="${INPUT:-${RUN_DIR}/samplesheet.csv}"
OUTDIR="${OUTDIR:-${RUN_DIR}/outputs}"
export NXF_WORK="${NXF_WORK:-${RUN_DIR}/work}"
LOG_DIR="${RUN_DIR}/logs"

# NXF_PODMAN_PULL_LOCK_DIR coordinates concurrent image pulls across tasks.
# Leave NXF_WORK on gscratch with force_mask="0700" in storage.conf so Podman
# can unpack image layers without hitting xattr restrictions.
export NXF_PODMAN_PULL_LOCK_DIR="${NXF_PODMAN_PULL_LOCK_DIR:-${NXF_WORK}/.podman-pull-locks}"

mkdir -p "${LOG_DIR}" "${NXF_WORK}" "${NXF_PODMAN_PULL_LOCK_DIR}"

# ============================================================
# Validate required settings
# ============================================================
if [[ -z "${WORKFLOW}" ]]; then
    echo "ERROR: WORKFLOW is not set. Edit the FILL IN section of this script."
    exit 1
fi
if [[ -z "${LABKEY_BASE_URL}" || "${LABKEY_BASE_URL}" == "https://labkey.example.org" ]]; then
    echo "ERROR: Set LABKEY_BASE_URL to your LabKey server URL."
    exit 1
fi
if [[ -z "${LABKEY_FOLDER}" || "${LABKEY_FOLDER}" == "/My/Project/Folder" ]]; then
    echo "ERROR: Set LABKEY_FOLDER to your LabKey folder path."
    exit 1
fi
if [[ ! -f "${INPUT}" ]]; then
    echo "ERROR: Samplesheet not found: ${INPUT}"
    echo "Edit samplesheet.csv in this run directory, or set INPUT=/path/to/samplesheet.csv"
    exit 1
fi
if [[ ! -x "${NEXTFLOW_BIN}" ]]; then
    echo "ERROR: Nextflow binary not found or not executable: ${NEXTFLOW_BIN}"
    echo "Set NEXTFLOW_BIN to your nextflow installation path."
    exit 1
fi

# ============================================================
# Banner
# ============================================================
echo "=========================================="
echo " GoodWorkflows Run"
echo "=========================================="
echo " SLURM_JOB_ID   : ${SLURM_JOB_ID:-local}"
echo " Run directory  : ${RUN_DIR}"
echo " Pipeline root  : ${PIPELINE_ROOT}"
echo " Workflow       : ${WORKFLOW}"
echo " Input          : ${INPUT}"
echo " Output dir     : ${OUTDIR}"
echo " Work dir       : ${NXF_WORK}"
echo " LabKey URL     : ${LABKEY_BASE_URL}"
echo " LabKey folder  : ${LABKEY_FOLDER}"
if [[ -n "${SLURM_JOB_ID:-}" ]]; then
    echo " Pre-pull mode  : inline in this SLURM allocation"
else
    echo " Pre-pull mode  : none (local run)"
fi
echo " Pull lock dir  : ${NXF_PODMAN_PULL_LOCK_DIR}"
echo "=========================================="

"${NEXTFLOW_BIN}" -version

# ============================================================
# Container image pre-pull (SLURM only)
# ============================================================
# For template-based SLURM runs, pre-pull happens inline in this same
# allocation before Nextflow starts. This is idempotent — images already
# present in the shared archive cache are skipped.
PREPULL_SCRIPT_PATH="${PIPELINE_ROOT}/scripts/slurm_prepull_images.sh"
if [[ -n "${SLURM_JOB_ID:-}" && -f "${PREPULL_SCRIPT_PATH}" ]]; then
    echo "Running inline container image pre-pull before Nextflow launch..."
    bash "${PREPULL_SCRIPT_PATH}" "$@" \
        || echo "WARNING: pre-pull finished with errors; tasks will load images on first use"
fi

# ============================================================
# Build Nextflow arguments
# ============================================================
declare -a NF_ARGS
NF_ARGS=(
    -log "${LOG_DIR}/nextflow.log"
    run "${PIPELINE_ROOT}/main.nf"
    -profile slurm
    -work-dir "${NXF_WORK}"
    -resume
    -ansi-log false
    --workflow "${WORKFLOW}"
    --input "${INPUT}"
    --outdir "${OUTDIR}"
    --labkey_base_url "${LABKEY_BASE_URL}"
    --labkey_folder "${LABKEY_FOLDER}"
)

if [[ -n "${NXF_PARAMS_FILE:-}" && -f "${NXF_PARAMS_FILE}" ]]; then
    NF_ARGS+=( -params-file "${NXF_PARAMS_FILE}" )
fi

# Forward any extra args passed to this script (e.g. --species_order human,macaque)
NF_ARGS+=( "$@" )

echo "Launching: ${NEXTFLOW_BIN} ${NF_ARGS[*]}"
"${NEXTFLOW_BIN}" "${NF_ARGS[@]}"
