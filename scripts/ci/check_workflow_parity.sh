#!/usr/bin/env bash
# check_workflow_parity.sh — Ensure workflow CLI lists stay aligned across launch surfaces.
#
# USAGE (from repo root):
#   bash scripts/ci/check_workflow_parity.sh
#   bash scripts/ci/check_workflow_parity.sh --strict-ci   # also fail when CI matrix omits a workflow
#
# Source of truth: main.nf supportedWorkflows inside run_pipeline.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

STRICT_CI=false
if [[ "${1:-}" == "--strict-ci" ]]; then
    STRICT_CI=true
fi

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MAIN_NF="${PROJECT_DIR}/main.nf"
RUN_SH="${PROJECT_DIR}/template/gw/run.sh"
CHECK_SH="${PROJECT_DIR}/template/gw/check_workflows.sh"
SCHEMA="${PROJECT_DIR}/nextflow_schema.json"
CI_YML="${PROJECT_DIR}/.github/workflows/ci.yml"

errors=0
warnings=0

extract_main_workflows() {
    awk '/supportedWorkflows\s*=\s*\[/{p=1; buf=$0; next} p{buf=buf $0} p && /\]/{p=0; print buf; buf=""}' \
        "${MAIN_NF}" 2>/dev/null | grep -oP "'[^']+'" | tr -d "'" | sort -u
}

extract_run_sh_workflows() {
    grep -oP 'VALID_WORKFLOWS=\(\K[^)]+' "${RUN_SH}" 2>/dev/null \
        | tr '"' ' ' | tr -s ' ' '\n' | grep -v '^$' | sort -u
}

extract_schema_workflows() {
    python3 - <<'PY' "${SCHEMA}"
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
wf = (
    data.get("definitions", {})
    .get("input_output_options", {})
    .get("properties", {})
    .get("workflow", {})
)
for v in sorted(wf.get("enum", [])):
    print(v)
PY
}

extract_ci_matrix_workflows() {
    sed -n '/^  workflow_smoke_tests:/,/^  module_smoke_tests:/p' "${CI_YML}" \
        | grep -E '^\s+workflow:\s*\[' \
        | head -1 \
        | sed -E 's/.*\[([^]]+)\].*/\1/' \
        | tr ',' '\n' \
        | sed 's/^ *//;s/ *$//' \
        | grep -v '^$' \
        | sort -u
}

extract_check_registry_workflows() {
    grep -E '^register ' "${CHECK_SH}" 2>/dev/null | awk '{print $2}' | sort -u
}

report_missing() {
    local label="$1"
    local severity="$2"  # error | warn
    shift 2
    local missing=("$@")
    if [[ ${#missing[@]} -eq 0 ]]; then
        return 0
    fi
    if [[ "${severity}" == "error" ]]; then
        echo -e "${RED}ERROR: ${label} missing:${NC}"
        errors=$((errors + 1))
    else
        echo -e "${YELLOW}WARN: ${label} missing:${NC}"
        warnings=$((warnings + 1))
    fi
    for w in "${missing[@]}"; do
        echo "  - ${w}"
    done
}

echo "Workflow parity check (source: main.nf supportedWorkflows)"
echo "Project: ${PROJECT_DIR}"
echo ""

mapfile -t MAIN_WFS < <(extract_main_workflows)
mapfile -t RUN_WFS < <(extract_run_sh_workflows)
mapfile -t SCHEMA_WFS < <(extract_schema_workflows)
mapfile -t CI_WFS < <(extract_ci_matrix_workflows)
mapfile -t REG_WFS < <(extract_check_registry_workflows)

if [[ ${#MAIN_WFS[@]} -eq 0 ]]; then
    echo -e "${RED}ERROR: Could not parse supportedWorkflows from ${MAIN_NF}${NC}"
    exit 1
fi

echo "main.nf (${#MAIN_WFS[@]}): ${MAIN_WFS[*]}"
echo "run.sh  (${#RUN_WFS[@]}): ${RUN_WFS[*]}"
echo ""

# main.nf -> run.sh (required)
missing_run=()
for w in "${MAIN_WFS[@]}"; do
    found=false
    for r in "${RUN_WFS[@]}"; do
        [[ "${w}" == "${r}" ]] && { found=true; break; }
    done
    ${found} || missing_run+=("${w}")
done
report_missing "template/gw/run.sh VALID_WORKFLOWS" "error" "${missing_run[@]}"

# Extra entries in run.sh not in main.nf
extra_run=()
for r in "${RUN_WFS[@]}"; do
    found=false
    for w in "${MAIN_WFS[@]}"; do
        [[ "${r}" == "${w}" ]] && { found=true; break; }
    done
    ${found} || extra_run+=("${r}")
done
report_missing "main.nf (stale run.sh entries)" "error" "${extra_run[@]}"

# main.nf -> schema enum (required)
missing_schema=()
for w in "${MAIN_WFS[@]}"; do
    found=false
    for s in "${SCHEMA_WFS[@]}"; do
        [[ "${w}" == "${s}" ]] && { found=true; break; }
    done
    ${found} || missing_schema+=("${w}")
done
report_missing "nextflow_schema.json workflow enum" "error" "${missing_schema[@]}"

# main.nf -> CI matrix (warn by default; error with --strict-ci)
missing_ci=()
for w in "${MAIN_WFS[@]}"; do
    found=false
    for c in "${CI_WFS[@]}"; do
        [[ "${w}" == "${c}" ]] && { found=true; break; }
    done
    ${found} || missing_ci+=("${w}")
done
if ${STRICT_CI}; then
    report_missing ".github/workflows/ci.yml workflow_smoke_tests matrix" "error" "${missing_ci[@]}"
else
    report_missing ".github/workflows/ci.yml workflow_smoke_tests matrix (use --strict-ci to fail)" "warn" "${missing_ci[@]}"
fi

# Registry entries not in main.nf (error)
extra_reg=()
for r in "${REG_WFS[@]}"; do
    found=false
    for w in "${MAIN_WFS[@]}"; do
        [[ "${r}" == "${w}" ]] && { found=true; break; }
    done
    ${found} || extra_reg+=("${r}")
done
report_missing "main.nf (stale check_workflows.sh register entries)" "error" "${extra_reg[@]}"

# Resolve repo-root test-data paths referenced in check_workflows.sh register blocks
echo ""
echo "── check_workflows.sh test-data samplesheet paths ──"
GW_DIR="${PROJECT_DIR}/template/gw"
while read -r ss_file; do
    [[ -z "${ss_file}" ]] && continue
    resolved="${PROJECT_DIR}/${ss_file}"
    if [[ -f "${resolved}" ]]; then
        echo -e "${GREEN}[OK]   ${ss_file}${NC}"
    else
        echo -e "${YELLOW}[WARN] missing: ${resolved}${NC}"
        warnings=$((warnings + 1))
    fi
done < <(grep -oE -- '--input test-data/[^"]+' "${CHECK_SH}" | sed 's/--input //' | sort -u)

echo ""
if [[ ${errors} -gt 0 ]]; then
    echo -e "${RED}Workflow parity FAILED (${errors} error(s), ${warnings} warning(s)).${NC}"
    echo "Sync template/gw/run.sh, nextflow_schema.json, and CI matrix with main.nf."
    echo "See .cursor/skills/goodworkflows-template-parity/SKILL.md and pipeline Completion Contract."
    exit 1
fi

if [[ ${warnings} -gt 0 ]]; then
    echo -e "${YELLOW}Workflow parity passed with ${warnings} warning(s).${NC}"
else
    echo -e "${GREEN}Workflow parity OK.${NC}"
fi

exit 0
