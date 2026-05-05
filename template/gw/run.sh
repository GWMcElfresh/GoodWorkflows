#!/usr/bin/env bash
# run.sh — Launch GoodWorkflows on Bazzite with local-gpu profile
#
# USAGE:
#   cd template/gw
#   bash run.sh --workflow <name> [--input samplesheet.csv] [extra nextflow params...]
#
# EXAMPLES:
#   bash run.sh --workflow ingest_export
#   bash run.sh --workflow integration --species_order human,macaque,mouse
#   bash run.sh --workflow ingest_tabulate --tabulate_id_cols cDNA_ID,SubjectId
#
# This launcher:
#   - Uses the local_gpu profile (Podman + NVIDIA GPU passthrough)
#   - Auto-detects PIPELINE_ROOT by walking up from template/gw/
#   - Creates a timestamped run directory under template/gw/runs/
#   - Does NOT require .netrc or LabKey credentials (URL-based samplesheets)
#   - Passes through all extra arguments to Nextflow
#
# Profile: local_gpu (Podman, --gpus all, --privileged, maxForks=1)

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- Detect paths ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [[ ! -f "${PIPELINE_ROOT}/main.nf" ]]; then
    echo -e "${RED}ERROR: Could not locate main.nf. Expected at: ${PIPELINE_ROOT}/main.nf${NC}"
    echo "Make sure you're running this from template/gw/ inside the GoodWorkflows repo."
    exit 1
fi

# --- Parse --workflow and --input from args ---
WORKFLOW=""
INPUT=""
REMAINING_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workflow)
            WORKFLOW="$2"
            shift 2
            ;;
        --workflow=*)
            WORKFLOW="${1#*=}"
            shift
            ;;
        --input)
            INPUT="$2"
            shift 2
            ;;
        --input=*)
            INPUT="${1#*=}"
            shift
            ;;
        *)
            REMAINING_ARGS+=("$1")
            shift
            ;;
    esac
done

# --- Validate workflow ---
if [[ -z "${WORKFLOW}" ]]; then
    echo -e "${RED}ERROR: --workflow is required.${NC}"
    echo "Valid options: integration, ingest_export, ingest_tabulate"
    echo ""
    echo "Usage: bash run.sh --workflow <name> [--input samplesheet.csv] [extra params...]"
    exit 1
fi

# Sync this list with main.nf supportedWorkflows whenever a new workflow is added.
VALID_WORKFLOWS=("integration" "ingest_export" "ingest_tabulate" "nmf_vae")
if [[ ! " ${VALID_WORKFLOWS[*]} " =~ " ${WORKFLOW} " ]]; then
    echo -e "${RED}ERROR: Invalid workflow '${WORKFLOW}'.${NC}"
    echo "Valid options: ${VALID_WORKFLOWS[*]}"
    exit 1
fi

# --- Default input ---
if [[ -z "${INPUT}" ]]; then
    INPUT="${SCRIPT_DIR}/samplesheet.csv"
fi

if [[ ! -f "${INPUT}" ]]; then
    echo -e "${RED}ERROR: Samplesheet not found: ${INPUT}${NC}"
    echo "Run fetch_example_data.sh first, or provide --input /path/to/samplesheet.csv"
    exit 1
fi

# --- Pre-flight: verify any path-mode or metadata_path-mode rows reference files that exist ---
if command -v awk &>/dev/null; then
    _path_col_idx=$(head -1 "${INPUT}" | tr ',' '\n' | grep -n '^path$' | cut -d: -f1 || true)
    _metadata_col_idx=$(head -1 "${INPUT}" | tr ',' '\n' | grep -n '^metadata_path$' | cut -d: -f1 || true)
    for _col_idx in "${_path_col_idx}" "${_metadata_col_idx}"; do
        if [[ -n "${_col_idx}" ]]; then
            _missing=0
            while IFS=, read -r -a _row; do
                _val="${_row[$(( _col_idx - 1 ))]}"
                _val="${_val//\"/}"  # strip any quotes
                if [[ -n "${_val}" && ! -f "${_val}" ]]; then
                    echo -e "${RED}ERROR: sample file not found: ${_val}${NC}"
                    _missing=1
                fi
            done < <(tail -n +2 "${INPUT}")
            if [[ "${_missing}" -eq 1 ]]; then
                echo "Ensure all files listed in the samplesheet of ${INPUT} exist before launching."
                exit 1
            fi
        fi
    done
fi

# --- Check Nextflow ---
if ! command -v nextflow &>/dev/null; then
    if [[ -x "${HOME}/bin/nextflow" ]]; then
        export PATH="${HOME}/bin:${PATH}"
    else
        echo -e "${RED}ERROR: Nextflow not found. Run setup.sh first.${NC}"
        exit 1
    fi
fi

# --- Ensure Arches4 cache directory exists (for NMF-VAE workflow) ---
if [[ "${WORKFLOW}" == "nmf_vae" ]]; then
    ARCHS4_DIR="${PIPELINE_ROOT}/.archs4"
    mkdir -p "${ARCHS4_DIR}"
    echo -e "${GREEN}Arches4 cache dir ready: ${ARCHS4_DIR}${NC}"
fi

# --- Create timestamped run directory ---
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
RUN_DIR="${SCRIPT_DIR}/runs/${WORKFLOW}_${TIMESTAMP}"
OUTDIR="${RUN_DIR}/outputs"
WORK_DIR="${RUN_DIR}/work"
LOG_DIR="${RUN_DIR}/logs"

mkdir -p "${OUTDIR}" "${WORK_DIR}" "${LOG_DIR}"

# --- Build Nextflow command ---
echo "=========================================="
echo " GoodWorkflows Run"
echo "=========================================="
echo " Workflow       : ${WORKFLOW}"
echo " Profile        : local_gpu"
echo " Pipeline root  : ${PIPELINE_ROOT}"
echo " Input          : ${INPUT}"
echo " Run directory  : ${RUN_DIR}"
echo " Output dir     : ${OUTDIR}"
echo " Work dir       : ${WORK_DIR}"
echo " Log dir        : ${LOG_DIR}"
echo "=========================================="

nextflow -version

# Build args array
NF_ARGS=(
    -log "${LOG_DIR}/nextflow.log"
    run "${PIPELINE_ROOT}/main.nf"
    -profile local_gpu
    -work-dir "${WORK_DIR}"
    -resume
    --workflow "${WORKFLOW}"
    --input "${INPUT}"
    --outdir "${OUTDIR}"
)

# Add any remaining args (e.g., --species_order, --scmodal_latent, etc.)
if [[ ${#REMAINING_ARGS[@]} -gt 0 ]]; then
    NF_ARGS+=("${REMAINING_ARGS[@]}")
fi

echo ""
echo "Launching: nextflow ${NF_ARGS[*]}"
echo ""

nextflow "${NF_ARGS[@]}"

EXIT_CODE=$?

echo ""
echo "=========================================="
if [[ ${EXIT_CODE} -eq 0 ]]; then
    echo -e "${GREEN} Pipeline completed successfully!${NC}"
    echo " Results: ${OUTDIR}"
else
    echo -e "${RED} Pipeline failed with exit code ${EXIT_CODE}${NC}"
    echo " Check logs: ${LOG_DIR}/nextflow.log"
fi
echo "=========================================="

exit ${EXIT_CODE}
