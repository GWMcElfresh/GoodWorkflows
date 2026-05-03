#!/usr/bin/env bash
# test_integration.sh — Test the integration workflow with pbmc3k URL data
#
# USAGE:
#   cd ~/GoodWorkflows
#   bash scripts/monthly_tests/test_integration.sh [BASE_URL]
#
# BASE_URL defaults to http://localhost:<port> where port is read from
# scripts/monthly_tests/data/http_port.txt (set by prep_pbmc3k.sh).
#
# This script:
#   1. Creates a URL-mode samplesheet pointing to served pbmc3k files
#   2. Runs nextflow integration workflow with -profile local_gpu
#   3. Checks for expected outputs (model_outputs, harmonized_outputs, counts, ingest)
#   4. Prints clear PASS/FAIL

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DATA_DIR="${SCRIPT_DIR}/data"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
WORK_DIR="/tmp/gw_test_integration_${TIMESTAMP}"
RUN_DIR="/tmp/gw_test_integration_run_${TIMESTAMP}"
OUTDIR="${RUN_DIR}/outputs"
LOG_DIR="${RUN_DIR}/logs"

mkdir -p "${OUTDIR}" "${WORK_DIR}" "${LOG_DIR}"

echo "=========================================="
echo " Test: Integration Workflow"
echo "=========================================="

# --- Check prerequisites ---
if ! command -v nextflow &>/dev/null; then
    if [[ -x "${HOME}/bin/nextflow" ]]; then
        export PATH="${HOME}/bin:${PATH}"
    else
        echo -e "${RED}ERROR: Nextflow not found. Run setup first.${NC}"
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

# --- Create URL-mode samplesheet ---
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
echo " Launching Integration Workflow"
echo "=========================================="
echo " Workflow       : integration"
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
    --workflow integration
    --input "${SAMPLESHEET}"
    --outdir "${OUTDIR}"
    --species_order human,macaque,mouse
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

# --- Check expected outputs ---
echo ""
echo "--- Checking outputs ---"

PASS=true

# Check ingest RDS files
for f in PBMC_HUMAN.rds PBMC_MACAQUE.rds PBMC_MOUSE.rds; do
    if [[ -f "${OUTDIR}/ingest/${f}" ]]; then
        echo -e "${GREEN}OK: ingest/${f}${NC}"
    else
        echo -e "${RED}MISSING: ingest/${f}${NC}"
        PASS=false
    fi
done

# Check count matrix directories
for sample in PBMC_HUMAN PBMC_MACAQUE PBMC_MOUSE; do
    COUNT_DIR="${OUTDIR}/counts/${sample}_counts"
    if [[ -d "${COUNT_DIR}" ]]; then
        echo -e "${GREEN}OK: counts/${sample}_counts/ (directory exists)${NC}"
        for inner in matrix.mtx features.tsv barcodes.tsv obs_meta.csv; do
            if [[ -f "${COUNT_DIR}/${inner}" ]]; then
                echo -e "  ${GREEN}OK: ${inner}${NC}"
            else
                echo -e "  ${RED}MISSING: ${inner}${NC}"
                PASS=false
            fi
        done
    else
        echo -e "${RED}MISSING: counts/${sample}_counts/${NC}"
        PASS=false
    fi
done

# Check harmonized outputs
if [[ -d "${OUTDIR}/harmonized/harmonized_outputs" ]]; then
    echo -e "${GREEN}OK: harmonized/harmonized_outputs/ (directory exists)${NC}"
    # Check for at least some expected files
    if [[ -f "${OUTDIR}/harmonized/harmonized_outputs/integration_manifest.csv" ]]; then
        echo -e "  ${GREEN}OK: integration_manifest.csv${NC}"
    else
        echo -e "  ${YELLOW}NOTE: integration_manifest.csv not found${NC}"
    fi
    # Check for at least one h5ad file
    H5AD_COUNT=$(find "${OUTDIR}/harmonized/harmonized_outputs" -name "*.h5ad" 2>/dev/null | wc -l)
    if [[ ${H5AD_COUNT} -gt 0 ]]; then
        echo -e "  ${GREEN}OK: Found ${H5AD_COUNT} harmonized .h5ad file(s)${NC}"
    else
        echo -e "  ${RED}MISSING: No .h5ad files found${NC}"
        PASS=false
    fi
else
    echo -e "${RED}MISSING: harmonized/harmonized_outputs/${NC}"
    PASS=false
fi

# Check scmodal model outputs
if [[ -d "${OUTDIR}/scmodal/model_outputs" ]]; then
    echo -e "${GREEN}OK: scmodal/model_outputs/ (directory exists)${NC}"
    for inner in ckpt.pth latent_clustered.h5ad training_history.csv; do
        if [[ -f "${OUTDIR}/scmodal/model_outputs/${inner}" ]]; then
            echo -e "  ${GREEN}OK: ${inner}${NC}"
        else
            echo -e "  ${YELLOW}NOTE: ${inner} not found${NC}"
        fi
    done
else
    echo -e "${RED}MISSING: scmodal/model_outputs/${NC}"
    PASS=false
fi

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
