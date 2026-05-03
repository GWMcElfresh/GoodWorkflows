#!/usr/bin/env bash
# run_all_tests.sh — Master script: runs all monthly GoodWorkflows tests in order
#
# USAGE:
#   cd ~/GoodWorkflows
#   bash scripts/monthly_tests/run_all_tests.sh
#
# This script:
#   1. Runs prep_pbmc3k.sh to prepare data and start HTTP server
#   2. Runs test_integration.sh
#   3. Runs test_ingest_export.sh
#   4. Runs test_ingest_tabulate.sh
#   5. Reports overall pass/fail
#   6. Cleans up the HTTP server
#
# Idempotent: prep_pbmc3k.sh skips R processing if data already exists.
# To force re-prep, delete scripts/monthly_tests/data/*.rds first.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DATA_DIR="${SCRIPT_DIR}/data"
HTTP_PID_FILE="${DATA_DIR}/http_server.pid"

# Track results
TOTAL=0
PASSED=0
FAILED=0
RESULTS=()

# --- Cleanup function ---
cleanup() {
    echo ""
    echo "--- Cleaning up ---"
    if [[ -f "${HTTP_PID_FILE}" ]]; then
        SERVER_PID="$(cat "${HTTP_PID_FILE}")"
        if kill -0 "${SERVER_PID}" 2>/dev/null; then
            echo "Stopping HTTP server (PID: ${SERVER_PID})..."
            kill "${SERVER_PID}" 2>/dev/null || true
            wait "${SERVER_PID}" 2>/dev/null || true
            echo -e "${GREEN}HTTP server stopped.${NC}"
        else
            echo -e "${YELLOW}HTTP server (PID: ${SERVER_PID}) not running (already stopped).${NC}"
        fi
        rm -f "${HTTP_PID_FILE}"
    else
        echo -e "${YELLOW}No HTTP server PID file found.${NC}"
    fi
}

# Register cleanup on exit (Ctrl-C, etc.)
trap cleanup EXIT

echo ""
echo -e "${BLUE}============================================================"
echo " GoodWorkflows Monthly Test Suite"
echo -e "${BLUE}============================================================${NC}"
echo " Date           : $(date)"
echo " Pipeline root  : ${PIPELINE_ROOT}"
echo " Scripts dir    : ${SCRIPT_DIR}"
echo " Data dir       : ${DATA_DIR}"
echo -e "${BLUE}============================================================${NC}"

# --- Check prerequisites ---
echo ""
echo "--- Checking prerequisites ---"

if ! command -v podman &>/dev/null; then
    echo -e "${RED}ERROR: podman not found.${NC}"
    exit 1
fi
echo -e "${GREEN}Podman: OK${NC}"

if ! command -v nextflow &>/dev/null; then
    if [[ -x "${HOME}/bin/nextflow" ]]; then
        export PATH="${HOME}/bin:${PATH}"
    else
        echo -e "${RED}ERROR: nextflow not found. Run template/gw/setup.sh first.${NC}"
        exit 1
    fi
fi
echo -e "${GREEN}Nextflow: OK ($(nextflow -version 2>&1 | head -1))${NC}"

if ! command -v curl &>/dev/null; then
    echo -e "${RED}ERROR: curl not found.${NC}"
    exit 1
fi
echo -e "${GREEN}curl: OK${NC}"

if ! command -v python3 &>/dev/null; then
    echo -e "${RED}ERROR: python3 not found.${NC}"
    exit 1
fi
echo -e "${GREEN}python3: OK${NC}"

# --- Phase 1: Prepare data ---
echo ""
echo -e "${BLUE}============================================================"
echo " Phase 1: Prepare pbmc3k Test Data"
echo -e "${BLUE}============================================================${NC}"

TOTAL=$((TOTAL + 1))

bash "${SCRIPT_DIR}/prep_pbmc3k.sh" 500
PREP_EXIT=$?

if [[ ${PREP_EXIT} -ne 0 ]]; then
    echo -e "${RED}prep_pbmc3k.sh failed with exit code ${PREP_EXIT}${NC}"
    RESULTS+=("PREP: FAIL")
    FAILED=$((FAILED + 1))
    echo -e "${RED}Cannot continue without test data.${NC}"
    exit 1
fi

# Read the base URL
BASE_URL=""
if [[ -f "${DATA_DIR}/base_url.txt" ]]; then
    BASE_URL="$(cat "${DATA_DIR}/base_url.txt")"
fi
if [[ -z "${BASE_URL}" ]]; then
    # Try to extract from prep output
    echo -e "${RED}ERROR: Could not determine BASE_URL from prep script.${NC}"
    exit 1
fi

echo -e "${GREEN}prep_pbmc3k.sh: PASS${NC}"
echo "Base URL: ${BASE_URL}"
PASSED=$((PASSED + 1))
RESULTS+=("PREP: PASS")

# --- Phase 2: Run tests ---
run_test() {
    local test_name="$1"
    local test_script="$2"
    local base_url="$3"

    echo ""
    echo -e "${BLUE}============================================================"
    echo " Phase: Test ${test_name}"
    echo -e "${BLUE}============================================================${NC}"

    TOTAL=$((TOTAL + 1))

    set +e
    bash "${test_script}" "${base_url}"
    local exit_code=$?
    set -e

    if [[ ${exit_code} -eq 0 ]]; then
        echo -e "${GREEN}${test_name}: PASS${NC}"
        PASSED=$((PASSED + 1))
        RESULTS+=("${test_name}: PASS")
    else
        echo -e "${RED}${test_name}: FAIL${NC}"
        FAILED=$((FAILED + 1))
        RESULTS+=("${test_name}: FAIL")
    fi
}

# Test 1: integration workflow
run_test "test_integration" "${SCRIPT_DIR}/test_integration.sh" "${BASE_URL}"

# Test 2: ingest_export workflow
run_test "test_ingest_export" "${SCRIPT_DIR}/test_ingest_export.sh" "${BASE_URL}"

# Test 3: ingest_tabulate workflow
run_test "test_ingest_tabulate" "${SCRIPT_DIR}/test_ingest_tabulate.sh" "${BASE_URL}"

# --- Final Summary ---
echo ""
echo -e "${BLUE}============================================================"
echo " Monthly Test Suite — Summary"
echo -e "${BLUE}============================================================${NC}"
echo ""

for result in "${RESULTS[@]}"; do
    if [[ "${result}" == *": PASS" ]]; then
        echo -e "  ${GREEN}✓${NC} ${result}"
    else
        echo -e "  ${RED}✗${NC} ${result}"
    fi
done

echo ""
echo " Total:  ${TOTAL}"
echo -e " Passed: ${GREEN}${PASSED}${NC}"
echo -e " Failed: ${RED}${FAILED}${NC}"
echo ""

if [[ ${FAILED} -eq 0 ]]; then
    echo -e "${GREEN}ALL TESTS PASSED${NC}"
    exit 0
else
    echo -e "${RED}SOME TESTS FAILED — check logs in /tmp/gw_test_*_run_*/logs/${NC}"
    exit 1
fi
