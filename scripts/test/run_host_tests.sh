#!/usr/bin/env bash
# run_host_tests.sh — Single entrypoint for GoodWorkflows multi-host local testing
#
# USAGE:
#   bash scripts/test/run_host_tests.sh                    # auto host, default tier
#   bash scripts/test/run_host_tests.sh --affected         # light + affected workflows only
#   bash scripts/test/run_host_tests.sh --host mac --tier stub
#   bash scripts/test/run_host_tests.sh --host wsl --tier stub   # full serial stub on WSL
#   bash scripts/test/run_host_tests.sh --host mac --tier real --workflow ingest_export
#
# Host profiles: template/gw/test-hosts.yaml
# Override: template/gw/.test-host (export GW_TEST_HOST=bazzite)

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GW_REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
export GW_REPO_ROOT

# shellcheck source=lib/host_profile.sh
source "${SCRIPT_DIR}/lib/host_profile.sh"

TEST_HOST="auto"
TEST_TIER="auto"
SINGLE_WF=""
AFFECTED=false
FAILED=0
PASSED=0
SKIPPED=0

usage() {
    cat <<EOF
Usage: bash scripts/test/run_host_tests.sh [options]

Options:
  --host auto|wsl|mac|bazzite   Test machine (default: auto-detect)
  --tier auto|light|stub|real   Test depth (default: host default_tier)
  --workflow NAME               Limit to one workflow CLI name
  --affected                    Light tier: only workflows touched in git diff
  --help                        Show this message

Examples:
  bash scripts/test/run_host_tests.sh
  bash scripts/test/run_host_tests.sh --affected
  bash scripts/test/run_host_tests.sh --host wsl --tier stub
  bash scripts/test/run_host_tests.sh --host mac --tier real --workflow ingest_export
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)     TEST_HOST="$2"; shift 2 ;;
        --host=*)   TEST_HOST="${1#*=}"; shift ;;
        --tier)     TEST_TIER="$2"; shift 2 ;;
        --tier=*)   TEST_TIER="${1#*=}"; shift ;;
        --workflow) SINGLE_WF="$2"; shift 2 ;;
        --workflow=*) SINGLE_WF="${1#*=}"; shift ;;
        --affected) AFFECTED=true; shift ;;
        --help|-h)  usage; exit 0 ;;
        *)
            echo -e "${RED}Unknown arg: $1${NC}" >&2
            usage
            exit 1
            ;;
    esac
done

resolve_test_host "${TEST_HOST}"
RESOLVED_TIER="$(resolve_tier "${GW_RESOLVED_HOST}" "${TEST_TIER}")"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  GoodWorkflows — Host Test Entrypoint                   ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo " Host:  ${GW_RESOLVED_HOST}"
echo " Tier:  ${RESOLVED_TIER}"
echo " Root:  ${GW_REPO_ROOT}"
echo ""

record_pass() { PASSED=$((PASSED + 1)); echo -e "${GREEN}[PASS]${NC} $*"; }
record_fail() { FAILED=$((FAILED + 1)); echo -e "${RED}[FAIL]${NC} $*"; }
record_skip() { SKIPPED=$((SKIPPED + 1)); echo -e "${YELLOW}[SKIP]${NC} $*"; }

# ── Map changed paths → workflow CLI names ───────────────────────────────────

affected_workflows() {
    local files=("$@")
    local wf
    declare -A seen=()

    add_wf() {
        [[ -z "${1:-}" ]] && return
        seen["$1"]=1
    }

    for f in "${files[@]}"; do
        case "${f}" in
            main.nf|nextflow.config|configs/*)
                add_wf ingest_export
                ;;
            workflows/batch_effect_assessments*|modules/local/batch_effect_assessments/*|test-data/batch_effect_assessments/*)
                add_wf batch_effect_assessments
                ;;
            workflows/integration*|modules/local/scmodal/*|modules/local/harmonize/*|modules/local/export/*|modules/local/ingest/*)
                add_wf integration
                add_wf ingest_export
                ;;
            workflows/ingest_export*|workflows/ingest_pipeline*)
                add_wf ingest_export
                ;;
            workflows/ingest_tabulate*|modules/local/tabulate/*)
                add_wf ingest_tabulate
                ;;
            workflows/nmf_vae*|modules/local/nmf_vae/*)
                add_wf nmf_vae
                ;;
            workflows/gex_mil*|modules/local/gex_mil/*|test-data/gex/*)
                add_wf gex_mil
                ;;
            workflows/tcr_mil*|modules/local/tcr_mil/*|test-data/tcr/*)
                add_wf tcr_mil
                ;;
            workflows/tcr_epitope*|modules/local/tcr_epitope/*)
                add_wf tcr_epitope
                ;;
            workflows/make_tcr*|modules/local/tcr_vector/*)
                add_wf make_tcr_vector_database
                ;;
            template/gw/check_workflows.sh|template/gw/run.sh|template/gw/test-hosts.yaml)
                add_wf ingest_export
                ;;
        esac
    done

    for wf in "${!seen[@]}"; do
        echo "${wf}"
    done | sort -u
}

git_changed_files() {
    git -C "${GW_REPO_ROOT}" diff --name-only HEAD 2>/dev/null || true
}

# ── Light tier ───────────────────────────────────────────────────────────────

run_light_tier() {
    local stub_profile
    stub_profile="$(host_stub_profile "${GW_RESOLVED_HOST}")"
    local real_profile=""
    if host_real_allowed "${GW_RESOLVED_HOST}"; then
        real_profile="$(host_real_profile "${GW_RESOLVED_HOST}")"
    fi

    echo "── Light tier: config + syntax ──"

    if command -v nextflow &>/dev/null; then
        if nextflow config -profile "${stub_profile}" "${GW_REPO_ROOT}/main.nf" > /dev/null 2>&1; then
            record_pass "nextflow config -profile ${stub_profile}"
        else
            record_fail "nextflow config -profile ${stub_profile}"
        fi
        if [[ -n "${real_profile}" ]]; then
            if nextflow config -profile "${real_profile}" "${GW_REPO_ROOT}/main.nf" > /dev/null 2>&1; then
                record_pass "nextflow config -profile ${real_profile}"
            else
                record_fail "nextflow config -profile ${real_profile}"
            fi
        fi
    else
        record_skip "nextflow not on PATH — config checks skipped"
    fi

    local shell_scripts=(
        "${GW_REPO_ROOT}/template/gw/check_workflows.sh"
        "${GW_REPO_ROOT}/template/gw/run.sh"
        "${GW_REPO_ROOT}/scripts/test/run_host_tests.sh"
        "${GW_REPO_ROOT}/scripts/test/lib/host_profile.sh"
        "${GW_REPO_ROOT}/scripts/ci/run_nextflow_smoke_tests.sh"
    )

    if ${AFFECTED}; then
        shell_scripts=()
        while IFS= read -r f; do
            [[ "${f}" == *.sh ]] && shell_scripts+=("${GW_REPO_ROOT}/${f}")
        done < <(git_changed_files)
        if [[ ${#shell_scripts[@]} -eq 0 ]]; then
            shell_scripts=(
                "${GW_REPO_ROOT}/template/gw/check_workflows.sh"
                "${GW_REPO_ROOT}/scripts/test/run_host_tests.sh"
            )
        fi
    fi

    for shf in "${shell_scripts[@]}"; do
        [[ -f "${shf}" ]] || continue
        if bash -n "${shf}" 2>/dev/null; then
            record_pass "bash -n ${shf#${GW_REPO_ROOT}/}"
        else
            record_fail "bash -n ${shf#${GW_REPO_ROOT}/}"
        fi
        if command -v shellcheck &>/dev/null; then
            if shellcheck -S warning "${shf}" > /dev/null 2>&1; then
                record_pass "shellcheck -S warning ${shf#${GW_REPO_ROOT}/}"
            else
                record_fail "shellcheck -S warning ${shf#${GW_REPO_ROOT}/}"
            fi
        fi
    done

    echo ""
    echo "── Light tier: workflow smoke ──"

    local workflows=()
    if [[ -n "${SINGLE_WF}" ]]; then
        workflows=("${SINGLE_WF}")
    elif ${AFFECTED}; then
        mapfile -t _changed < <(git_changed_files)
        mapfile -t workflows < <(affected_workflows "${_changed[@]}")
        if [[ ${#workflows[@]} -eq 0 ]]; then
            record_skip "no affected workflow mapped from git diff"
            return
        fi
    else
        workflows=(ingest_export)
    fi

    if ! command -v nextflow &>/dev/null; then
        record_skip "nextflow not on PATH — workflow smoke skipped"
        return
    fi

    local wf smoke_args=()
    for wf in "${workflows[@]}"; do
        smoke_args=()
        if [[ "${wf}" == "integration" ]]; then
            smoke_args=(--scmodal_use_cpu true)
        fi
        if bash "${GW_REPO_ROOT}/scripts/ci/run_nextflow_smoke_tests.sh" workflow "${wf}" "${smoke_args[@]}"; then
            record_pass "CI smoke: workflow ${wf}"
        else
            record_fail "CI smoke: workflow ${wf}"
        fi
    done
}

# ── Stub / real tiers (delegate to check_workflows.sh) ───────────────────────

run_check_workflows_tier() {
    local tier="$1"
    local args=(--host "${GW_RESOLVED_HOST}" --tier "${tier}")
    [[ -n "${SINGLE_WF}" ]] && args+=(--workflow "${SINGLE_WF}")

    if bash "${GW_REPO_ROOT}/template/gw/check_workflows.sh" "${args[@]}"; then
        record_pass "check_workflows.sh --tier ${tier}"
    else
        record_fail "check_workflows.sh --tier ${tier}"
    fi
}

case "${RESOLVED_TIER}" in
    light)
        run_light_tier
        ;;
    stub|real)
        if [[ "${RESOLVED_TIER}" == "real" ]]; then
            if ! host_real_allowed "${GW_RESOLVED_HOST}"; then
                echo -e "${RED}Real tier not allowed on host ${GW_RESOLVED_HOST}.${NC}"
                exit 1
            fi
            if ! check_host_requirements "${GW_RESOLVED_HOST}" 2>/dev/null; then
                echo -e "${YELLOW}Warning: host requirements may not be met for real runs.${NC}"
            fi
        fi
        run_check_workflows_tier "${RESOLVED_TIER}"
        ;;
    *)
        echo -e "${RED}Unknown tier: ${RESOLVED_TIER}${NC}"
        exit 1
        ;;
esac

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Host Test Summary                                      ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo -e "  Host:    ${GW_RESOLVED_HOST}"
echo -e "  Tier:    ${RESOLVED_TIER}"
echo -e "  ${GREEN}Passed:  ${PASSED}${NC}"
echo -e "  ${RED}Failed:  ${FAILED}${NC}"
if [[ ${SKIPPED} -gt 0 ]]; then
    echo -e "  ${YELLOW}Skipped: ${SKIPPED}${NC}"
fi
echo ""

if [[ ${FAILED} -gt 0 ]]; then
    exit 1
fi
exit 0
