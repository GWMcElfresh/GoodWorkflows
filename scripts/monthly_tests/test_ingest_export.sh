#!/usr/bin/env bash
# test_ingest_export.sh — Run the ingest_export workflow with pbmc3k URL-mode data
#
# USAGE:
#   cd ~/GoodWorkflows
#   bash scripts/monthly_tests/test_ingest_export.sh [BASE_URL]
#
# BASE_URL defaults to http://localhost:<port> where port is read from
# scripts/monthly_tests/data/http_port.txt (set by prep_pbmc3k.sh).
#
# Outputs: per-sample count matrix directories (matrix.mtx, features.tsv, barcodes.tsv)

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DATA_DIR="${SCRIPT_DIR}/data"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
WORK_DIR="/tmp/gw_test_ingest_export_${TIMESTAMP}"
RUN_DIR="/tmp/gw_test_ingest_export_run_${TIMESTAMP}"
OUTDIR="${RUN_DIR}/outputs"
LOG_DIR="${RUN_DIR}/logs"

mkdir -p "${OUTDIR}" "${WORK_DIR}" "${LOG_DIR}"

echo "=========================================="
echo " Test: ingest_export workflow"
echo "=========================================="

# --- Check Nextflow ---
if ! command -v nextflow &>/dev/null; then
    if [[ -x "${HOME}/bin/nextflow" ]]; then
        export PATH="${HOME}/bin:${PATH}"
    else
        echo -e "${RED}ERROR: Nextflow not found.${NC}"
        exit 1
    fi
fi
echo -e "${GREEN}Nextflow found: $(nextflow -version 2>&1 | head -1)${NC}"

if ! command -v podman &>/dev/null; then
    echo -e "${RED}ERROR: podman not found.${NC}"
    exit 1
fi

# --- Get BASE_URL ---
BASE_URL="${1:-}"
if [[ -z "${BASE_URL}" ]]; then
    if [[ -f "${DATA_DIR}/base_url.txt" ]]; then
        BASE_URL="$(cat "${DATA_DIR}/base_url.txt")"
    elif [[ -f "${DATA_DIR}/http_port.txt" ]]; then
        HTTP_PORT="$(cat "${DATA_DIR}/http_port.txt")"
        BASE_URL="http://localhost:${HTTP_PORT}"
    else
        echo -e "${RED}ERROR: No BASE_URL provided and no http_port.txt found.${NC}"
        echo "Run prep_pbmc3k.sh first, or pass BASE_URL as argument."
        exit 1
    fi
fi

# Verify HTTP server is reachable
if ! curl -sf "${BASE_URL}/" &>/dev/null; then
    echo -e "${RED}ERROR: HTTP server not reachable at ${BASE_URL}${NC}"
    echo "Run prep_pbmc3k.sh first to start the server."
    exit 1
fi
echo -e "${GREEN}HTTP server reachable at ${BASE_URL}${NC}"

# --- Generate URL-mode samplesheet ---
SAMPLESHEET="${RUN_DIR}/samplesheet.csv"
cat > "${SAMPLESHEET}" <<EOF
sample_id,output_file_id,url,path,species
PBMC_HUMAN,,${BASE_URL}/pbmc3k_human.rds,,human
PBMC_MACAQUE,,${BASE_URL}/pbmc3k_macaque.rds,,macaque
PBMC_MOUSE,,${BASE_URL}/pbmc3k_mouse.rds,,mouse
EOF

echo "Samplesheet created: ${SAMPLESHEET}"
echo "Contents:"
cat "${SAMPLESHEET}"

# --- Run Nextflow ---
echo ""
echo "=========================================="
echo " Launching ingest_export Workflow"
echo "=========================================="
echo " Workflow       : ingest_export"
echo " Profile        : local_gpu"
echo " Pipeline root  : ${PIPELINE_ROOT}"
echo " Input          : ${SAMPLESHEET}"
echo " Output dir     : ${OUTDIR}"
echo " Work dir       : ${WORK_DIR}"
echo " Log dir        : ${LOG_DIR}"
echo "=========================================="

NF_ARGS=(
    -log "${LOG_DIR}/nextflow.log"
    run "${PIPELINE_ROOT}/main.nf"
    -profile local_gpu
    -work-dir "${WORK_DIR}"
    --workflow ingest_export
    --input "${SAMPLESHEET}"
    --outdir "${OUTDIR}"
)

echo ""
echo "Command: nextflow ${NF_ARGS[*]}"
echo ""

set +e
nextflow "${NF_ARGS[@]}"
NF_EXIT=$?
set -e

if [[ ${NF_EXIT} -ne 0 ]]; then
    echo ""
    echo -e "${RED}=========================================="
    echo " RESULT: FAIL"
    echo -e "${RED}==========================================${NC}"
    echo "Nextflow exited with code ${NF_EXIT}"
    echo "Log file: ${LOG_DIR}/nextflow.log"
    echo ""
    echo "Last 50 lines of log:"
    tail -50 "${LOG_DIR}/nextflow.log" 2>/dev/null || echo "(no log file found)"
    exit 1
fi

# --- Validate outputs ---
echo ""
echo "--- Checking expected outputs ---"
PASS=true

for sample in PBMC_HUMAN PBMC_MACAQUE PBMC_MOUSE; do
    COUNTS_DIR="${OUTDIR}/counts/${sample}_counts"
    if [[ -d "${COUNTS_DIR}" ]]; then
        echo -e "${GREEN}OK: counts/${sample}_counts/ (directory exists)${NC}"
        for f in matrix.mtx features.tsv barcodes.tsv; do
            if [[ -f "${COUNTS_DIR}/${f}" ]]; then
                echo -e "  ${GREEN}OK: ${f}${NC}"
            else
                echo -e "  ${RED}MISSING: ${f}${NC}"
                PASS=false
            fi
        done
    else
        echo -e "${RED}MISSING: counts/${sample}_counts/${NC}"
        PASS=false
    fi
done

# --- Result ---
echo ""
if [[ "${PASS}" == "true" ]]; then
    echo -e "${GREEN}=========================================="
    echo " RESULT: PASS"
    echo -e "${GREEN}==========================================${NC}"
    echo "All expected outputs verified."
    echo "Results directory: ${OUTDIR}"
    exit 0
else
    echo -e "${RED}=========================================="
    echo " RESULT: FAIL"
    echo -e "${RED}==========================================${NC}"
    echo "Some expected outputs are missing."
    echo "Results directory: ${OUTDIR}"
    echo "Log file: ${LOG_DIR}/nextflow.log"
    exit 1
fi
