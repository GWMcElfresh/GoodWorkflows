#!/usr/bin/env bash
# check_workflows.sh — Sanity check + serial runner for GoodWorkflows
#
# TWO MODES:
#   --stub (default)    Quick `-stub-run -profile test` validation.
#                       No containers needed. Verifies pipeline compiles,
#                       samplesheets parse, channels match. Good for
#                       pre-commit / CI gate.
#
#   --real              Full pipeline execution via Podman containers on
#                       real test data (the RDS files from fetch_example_data.sh).
#                       Requires: containers pulled (bash setup.sh), GPU
#                       available for GPU-backed workflows.
#
# USAGE:
#   bash check_workflows.sh                           # stub-run (default)
#   bash check_workflows.sh --real                    # real runs on test data
#   bash check_workflows.sh --workflow nmf_vae        # single workflow, stub
#   bash check_workflows.sh --real --workflow nmf_vae # single workflow, real
#   bash check_workflows.sh --help                    # show usage
#
# PURPOSE:
#   Validates every workflow compiles (--stub, default) or actually runs
#   on toy test data (--real). Pre-flights: Nextflow availability, samplesheet
#   integrity, data files. Auto-discovers workflows from main.nf — anything in
#   supportedWorkflows that isn't in WORKFLOW_REGISTRY gets a default entry.
#   Reports a pass/fail summary table at the end.
#
# MAINTAINING:
#   When adding a new workflow that needs a NON-DEFAULT samplesheet or
#   extra flags, add ONE entry to WORKFLOW_REGISTRY below:
#
#     "workflow_name|expected_col|stub_args|real_args"
#
#   - expected_col: column the samplesheet must have for pre-flight check
#   - stub_args:    flags for 'nextflow run -stub-run'
#     e.g. '--input tabulate_samplesheet.csv' or 'samplesheet.csv' (bare)
#   - real_args:    extra flags for 'bash run.sh'
#     e.g. '--input tcr_epitope_samplesheet.csv --binding_model_path tcr_epitope_models'
#
#   If a workflow just uses the default samplesheet.csv with no extra flags,
#   you don't need to register it at all — auto-discovery handles it.

set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ── Paths ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS=()
STUB_MODE=true
SINGLE_WF=""

# ═══════════════════════════════════════════════════════════════════════════════
# WORKFLOW REGISTRY (overrides for non-default samplesheets / flags)
#
# Add an entry here ONLY if the workflow uses a different samplesheet than
# samplesheet.csv, or needs extra arguments.  Everything else is auto-discovered
# from main.nf → supportedWorkflows.
# ═══════════════════════════════════════════════════════════════════════════════

declare -A WF_STUB
declare -A WF_REAL
declare -A WF_COL

# Format: register <name> <expected_col> <stub_args> <real_args>
register() {
    WF_COL[$1]="$2"
    WF_STUB[$1]="$3"
    WF_REAL[$1]="$4"
}

# --- Workflows with non-default samplesheets or extra flags ---
register ingest_tabulate metadata_path \
    "--input tabulate_samplesheet.csv" "--input tabulate_samplesheet.csv"

register nmf_vae lambda_graph \
    "--input nmf_vae_samplesheet.csv" "--input nmf_vae_samplesheet.csv"

register tcr_epitope epitope_file \
    "--input tcr_epitope_samplesheet.csv" "--input tcr_epitope_samplesheet.csv --binding_model_path tcr_epitope_models"

# Workflows that use the default samplesheet.csv but have unique column needs
# are documented here for the pre-flight column check:
register gex_mil SubjectId "samplesheet.csv" ""

register batch_effect_assessments batch_column \
    "--input test-data/batch_effect_assessments/samplesheet.csv" \
    "--input test-data/batch_effect_assessments/samplesheet.csv"

# ═══════════════════════════════════════════════════════════════════════════════

# ── Pre-parse: extract workflow names for --help ─────────────────────────────
declare -A ALL_WORKFLOWS
NF_WORKFLOWS=()

if [[ -f "${PIPELINE_ROOT}/main.nf" ]]; then
    NF_RAW=$(awk '/supportedWorkflows\s*=\s*\[/{p=1; buf=$0; next} p{buf=buf $0} p && /\]/{p=0; print buf; buf=""}' \
        "${PIPELINE_ROOT}/main.nf" 2>/dev/null || true)
    if [[ -n "${NF_RAW}" ]]; then
        while IFS= read -r wf; do
            [[ -n "${wf}" ]] && NF_WORKFLOWS+=("${wf}")
        done < <(echo "${NF_RAW}" | grep -oP "'[^']+'" | tr -d "'")
    fi
fi

for wf in "${!WF_STUB[@]}"; do ALL_WORKFLOWS["${wf}"]="${wf}"; done
for wf in "${NF_WORKFLOWS[@]}"; do
    if [[ -z "${ALL_WORKFLOWS[${wf}]-}" ]]; then
        ALL_WORKFLOWS["${wf}"]="${wf}"
    fi
done
mapfile -t WORKFLOW_NAMES < <(for wf in "${!ALL_WORKFLOWS[@]}"; do echo "${wf}"; done | sort)

# ── Parse args ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --real)     STUB_MODE=false; shift ;;
        --stub)     STUB_MODE=true;  shift ;;
        --workflow) SINGLE_WF="$2";  shift 2 ;;
        --workflow=*) SINGLE_WF="${1#*=}"; shift ;;
        --help|-h)
            echo "Usage: bash check_workflows.sh [--real] [--workflow <name>]"
            echo ""
            echo "Modes:"
            echo "  (no flag)  Quick stub-run validation (default)"
            echo "             No containers needed — validates compilation."
            echo "  --real     Full pipeline execution on toy test data."
            echo "             Requires: 'bash setup.sh' first, then"
            echo "             'bash fetch_example_data.sh' to generate data."
            echo ""
            echo "Options:"
            echo "  --workflow X  Run a single workflow instead of all"
            echo "  --help        Show this message"
            echo ""
            echo "Registered workflows:"
            for wf in "${!ALL_WORKFLOWS[@]}"; do echo "  - ${wf}"; done
            echo ""
            echo "Prerequisites for --real mode:"
            echo "  - Container images pulled:  bash setup.sh"
            echo "  - Test data generated:      bash fetch_example_data.sh"
            echo "  - Nextflow on PATH"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown arg: $1${NC}"
            exit 1
            ;;
    esac
done

# ═══════════════════════════════════════════════════════════════════════════════
# Auto-register: any workflow in main.nf not in the registry gets defaults
# ═══════════════════════════════════════════════════════════════════════════════

for wf in "${NF_WORKFLOWS[@]}"; do
    if [[ -z "${WF_STUB[${wf}]-}" ]]; then
        WF_COL["${wf}"]="path"
        WF_STUB["${wf}"]="samplesheet.csv"
        WF_REAL["${wf}"]=""
    fi
done

# ── Pre-flight: Nextflow ─────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  GoodWorkflows — Workflow Sanity Check                  ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo " Mode:        $(${STUB_MODE} && echo 'stub-run (quick)' || echo 'REAL (containers)')"
echo " Pipeline:    ${PIPELINE_ROOT}"
echo " Template:    ${SCRIPT_DIR}"
echo ""

errors=0
if command -v nextflow &>/dev/null 2>&1; then
    echo -e "${GREEN}[OK]   Nextflow found: $(nextflow -version 2>&1 | head -1)${NC}"
else
    echo -e "${RED}[FAIL] nextflow not found on PATH${NC}"
    errors=$((errors + 1))
fi

# ── Pre-flight: workflow list parity ─────────────────────────────────────────
echo ""
echo "── Workflow list parity ──"
registry_only=()
for wf in "${WORKFLOW_NAMES[@]}"; do
    # Check if this was auto-added (not in WF_STUB but in ALL_WORKFLOWS via NF)
    if [[ -z "${WF_STUB[${wf}]-}" ]]; then
        registry_only+=("${wf}")
    fi
done

if [[ ${#NF_WORKFLOWS[@]} -eq 0 ]]; then
    echo -e "${YELLOW}[WARN] Could not extract workflow list from main.nf${NC}"
    echo "  Using ${#WORKFLOW_NAMES[@]} registry entries only."
else
    # Check NF workflows not in registry
    for nf_wf in "${NF_WORKFLOWS[@]}"; do
        if [[ -z "${WF_STUB[${nf_wf}]-}" ]]; then
            echo -e "${BLUE}[INFO] '${nf_wf}' auto-added from main.nf (default samplesheet.csv)${NC}"
            echo "  Add to WORKFLOW_REGISTRY in this script if it needs special flags."
        fi
    done
    # Check registry workflows not in NF
    for wf in "${!WF_STUB[@]}"; do
        found=false
        for nf_wf in "${NF_WORKFLOWS[@]}"; do
            [[ "${wf}" == "${nf_wf}" ]] && { found=true; break; }
        done
        if ! ${found}; then
            echo -e "${YELLOW}[WARN] '${wf}' is in WORKFLOW_REGISTRY but NOT in main.nf${NC}"
            echo "  Either add to main.nf supportedWorkflows or remove from registry."
            errors=$((errors + 1))
        fi
    done
    if [[ ${errors} -eq 0 ]]; then
        echo -e "${GREEN}[OK]   ${#WORKFLOW_NAMES[@]} workflows total (${#WF_STUB[@]} registered, $(( ${#WORKFLOW_NAMES[@]} - ${#WF_STUB[@]} )) auto-discovered from main.nf)${NC}"
    fi
fi

# ── Pre-flight: samplesheet + data checks ────────────────────────────────────
echo ""
echo "── Samplesheet & data pre-flight ──"
for wf_name in "${WORKFLOW_NAMES[@]}"; do
    stub_args="${WF_STUB[${wf_name}]-samplesheet.csv}"
    ss_col="${WF_COL[${wf_name}]-path}"

    # Resolve samplesheet path
    if echo "${stub_args}" | grep -q -- "--input"; then
        ss_file=$(echo "${stub_args}" | sed 's/.*--input //' | awk '{print $1}')
    else
        ss_file="${stub_args}"
    fi
    ss_path="${SCRIPT_DIR}/${ss_file}"

    if [[ ! -f "${ss_path}" ]]; then
        echo -e "${YELLOW}[WARN] ${wf_name}: samplesheet '${ss_file}' not found${NC}"
        echo "  Run 'bash fetch_example_data.sh' to generate it."
        continue
    fi

    # Column check
    header=$(head -1 "${ss_path}" 2>/dev/null || echo "")
    if [[ -n "${header}" ]]; then
        has_sample=$(echo "${header}" | tr ',' '\n' | grep -c '^sample_id$' || true)
        if [[ "${has_sample}" -eq 0 ]]; then
            echo -e "${YELLOW}[WARN] ${wf_name}: samplesheet missing 'sample_id' column${NC}"
        fi
        has_col=$(echo "${header}" | tr ',' '\n' | grep -c "^${ss_col}$" || true)
        if [[ "${has_col}" -eq 0 ]]; then
            echo -e "${BLUE}[INFO] ${wf_name}: expected column '${ss_col}' not found in samplesheet${NC}"
        fi
    fi

    # File existence check for path-based rows
    if command -v awk &>/dev/null; then
        path_col=$(head -1 "${ss_path}" 2>/dev/null | tr ',' '\n' | grep -n '^path$' | cut -d: -f1 || true)
        if [[ -n "${path_col}" ]]; then
            missing=0
            while IFS=, read -r -a row; do
                val="${row[$((path_col - 1))]}"
                val="${val//\"/}"
                if [[ -n "${val}" && ! -f "${val}" ]]; then
                    missing=$((missing + 1))
                fi
            done < <(tail -n +2 "${ss_path}")
            if [[ "${missing}" -gt 0 ]]; then
                echo -e "${YELLOW}[WARN] ${wf_name}: ${missing} path(s) point to missing files${NC}"
            fi
        fi
    fi
    echo -e "${GREEN}[OK]   ${wf_name}: samplesheet ready at ${ss_path}${NC}"
done

if [[ ${errors} -gt 0 ]]; then
    echo ""
    echo -e "${RED}${errors} pre-flight error(s). Fix before running workflows.${NC}"
fi

# ── Assemble the run list ────────────────────────────────────────────────────
RUN_LIST=()
for wf_name in "${WORKFLOW_NAMES[@]}"; do
    if [[ -n "${SINGLE_WF}" && "${wf_name}" != "${SINGLE_WF}" ]]; then
        continue
    fi
    RUN_LIST+=("${wf_name}")
done

if [[ ${#RUN_LIST[@]} -eq 0 ]]; then
    echo -e "${RED}No workflows to run.${NC}"
    echo "  Check --workflow name or WORKFLOW_REGISTRY entries."
    exit 1
fi

echo ""
echo "══ Running ${#RUN_LIST[@]} workflow(s) $(${STUB_MODE} && echo '(stub-run)' || echo '(REAL mode)') ══"
echo ""

TOTAL=0; PASSED=0; FAILED=0

# ── Verify test profile loads ────────────────────────────────────────────────
if ${STUB_MODE}; then
    nextflow config -profile test "${PIPELINE_ROOT}/main.nf" > /dev/null 2>&1 || \
        echo -e "${YELLOW}[WARN] 'nextflow config -profile test' failed — config may be broken${NC}"
fi

# ── Main run loop ─────────────────────────────────────────────────────────────
for wf_name in "${RUN_LIST[@]}"; do
    stub_args="${WF_STUB[${wf_name}]-samplesheet.csv}"
    real_args="${WF_REAL[${wf_name}]-}"

    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    OUTPUT_DIR="${SCRIPT_DIR}/runs/check_${wf_name}_${TIMESTAMP}"
    WORK_DIR="${OUTPUT_DIR}/work"
    LOG_DIR="${OUTPUT_DIR}/logs"
    mkdir -p "${OUTPUT_DIR}" "${WORK_DIR}" "${LOG_DIR}"

    # Latest symlink for debugging
    LATEST_LINK="${SCRIPT_DIR}/runs/latest"
    rm -f "${LATEST_LINK}"
    ln -s "${OUTPUT_DIR}" "${LATEST_LINK}"

    if ${STUB_MODE}; then
        INPUT_FLAG=""
        EXTRA=""
        if echo "${stub_args}" | grep -q -- "--input"; then
            ss_file=$(echo "${stub_args}" | sed 's/.*--input //' | awk '{print $1}')
            INPUT_FLAG="--input ${SCRIPT_DIR}/${ss_file}"
            EXTRA=$(echo "${stub_args}" | sed 's/--input [^ ]* *//g')
        elif [[ -n "${stub_args}" ]] && [[ -f "${SCRIPT_DIR}/${stub_args}" ]]; then
            INPUT_FLAG="--input ${SCRIPT_DIR}/${stub_args}"
        elif [[ -f "${SCRIPT_DIR}/samplesheet.csv" ]]; then
            INPUT_FLAG="--input ${SCRIPT_DIR}/samplesheet.csv"
        fi

        # shellcheck disable=SC2206
        CMD=(nextflow run "${PIPELINE_ROOT}/main.nf" -stub-run -profile test \
            --workflow "${wf_name}" ${INPUT_FLAG} ${EXTRA} \
            --outdir "${OUTPUT_DIR}/outputs")
    else
        INPUT_FLAG=""
        EXTRA=""
        if echo "${real_args}" | grep -q -- "--input"; then
            ss_file=$(echo "${real_args}" | sed 's/.*--input //' | awk '{print $1}')
            INPUT_FLAG="--input ${SCRIPT_DIR}/${ss_file}"
            EXTRA=$(echo "${real_args}" | sed 's/--input [^ ]* *//g')
        fi
        # shellcheck disable=SC2206
        CMD=(bash "${SCRIPT_DIR}/run.sh" --workflow "${wf_name}" ${INPUT_FLAG} ${EXTRA})
    fi

    echo -e "${BOLD}[$((TOTAL + 1))/${#RUN_LIST[@]}] ${wf_name}${NC}"
    echo "  ${CMD[*]}" | head -c 250
    echo ""

    START_TS=$(date +%s)
    set +e
    if ${STUB_MODE}; then
        "${CMD[@]}" > "${LOG_DIR}/nextflow.log" 2>&1
        EXIT_CODE=$?
        if grep -qi "error\|exception\|MissingOutputFile" "${LOG_DIR}/nextflow.log" 2>/dev/null; then
            EXIT_CODE=1
        fi
    else
        "${CMD[@]}" 2>&1 | tee "${LOG_DIR}/run.log"
        EXIT_CODE=${PIPESTATUS[0]}
    fi
    set -euo pipefail
    END_TS=$(date +%s)
    DURATION=$((END_TS - START_TS))

    TOTAL=$((TOTAL + 1))
    if [[ ${EXIT_CODE} -eq 0 ]]; then
        PASSED=$((PASSED + 1))
        echo -e "  ${GREEN}✓ PASS${NC} (${DURATION}s)"
        RESULTS+=("${wf_name}|PASS|${DURATION}s")
    else
        FAILED=$((FAILED + 1))
        echo -e "  ${RED}✗ FAIL${NC} (${DURATION}s)"
        RESULTS+=("${wf_name}|FAIL|${DURATION}s")
        if ${STUB_MODE}; then
            tail -15 "${LOG_DIR}/nextflow.log" 2>/dev/null | sed 's/^/    /'
        else
            tail -15 "${LOG_DIR}/run.log" 2>/dev/null | sed 's/^/    /'
        fi
    fi
    echo ""
done

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Results Summary                                        ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
printf "  %-20s %-6s %s\n" "Workflow" "Status" "Duration"
printf "  %-20s %-6s %s\n" "────────────────────" "──────" "────────"
for result in "${RESULTS[@]}"; do
    IFS='|' read -r name status duration <<< "${result}"
    if [[ "${status}" == "PASS" ]]; then
        printf "  ${GREEN}%-20s %-6s${NC} %s\n" "${name}" "${status}" "${duration}"
    else
        printf "  ${RED}%-20s %-6s${NC} %s\n" "${name}" "${status}" "${duration}"
    fi
done
echo ""
echo "  Total:  ${TOTAL}"
echo -e "  ${GREEN}Passed: ${PASSED}${NC}"
echo -e "  ${RED}Failed: ${FAILED}${NC}"
echo ""

if [[ ${FAILED} -gt 0 ]]; then
    echo -e "${YELLOW}Check logs in ${SCRIPT_DIR}/runs/check_*/logs/${NC}"
fi
if ${STUB_MODE} && [[ ${FAILED} -eq 0 ]]; then
    echo -e "${GREEN}All stub-run checks passed!${NC}"
    echo "  Pipeline compiles and validates for all ${TOTAL} workflows."
    echo "  For actual end-to-end execution on test data:"
    echo "    bash check_workflows.sh --real"
fi

exit ${FAILED}
