#!/usr/bin/env bash
# host_profile.sh — Resolve GoodWorkflows test host and tier from test-hosts.yaml
#
# Usage (source, do not execute directly):
#   source scripts/test/lib/host_profile.sh
#   resolve_test_host auto
#   host_default_tier mac
#   workflow_real_allowed mac integration
#
# Environment:
#   GW_TEST_HOST     — explicit host (wsl|mac|bazzite)
#   GW_REPO_ROOT     — repo root (auto-detected if unset)

set -euo pipefail

# ── Paths ────────────────────────────────────────────────────────────────────
if [[ -z "${GW_REPO_ROOT:-}" ]]; then
    _HOST_PROFILE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    GW_REPO_ROOT="$(cd "${_HOST_PROFILE_DIR}/../../.." && pwd)"
fi
GW_TEST_HOSTS_YAML="${GW_REPO_ROOT}/template/gw/test-hosts.yaml"
GW_TEST_HOST_LOCAL="${GW_REPO_ROOT}/template/gw/.test-host"

# Resolved host (set by resolve_test_host)
GW_RESOLVED_HOST=""

# GPU workflows (shared across hosts; populated on first yaml read)
declare -a GW_GPU_WORKFLOWS=()
declare -a GW_CPU_WORKFLOWS=()

# ── YAML helpers (minimal parser for test-hosts.yaml structure) ──────────────

_yaml_host_block() {
    local host="$1"
    awk -v h="${host}" '
        $0 ~ "^  " h ":$" { found=1; next }
        found && /^  [a-z_]+:$/ { exit }
        found { print }
    ' "${GW_TEST_HOSTS_YAML}" 2>/dev/null || true
}

_yaml_scalar() {
    local host="$1" key="$2"
    _yaml_host_block "${host}" | grep -E "^    ${key}:" | head -1 | sed -E "s/^    ${key}: *//" | tr -d '"' || true
}

_yaml_list() {
    local host="$1" key="$2"
    local inline
    inline=$(_yaml_host_block "${host}" | grep -E "^    ${key}:" | head -1 | sed -E "s/^    ${key}: *//" || true)
    if [[ "${inline}" == \[* ]]; then
        echo "${inline}" | tr -d '[]' | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -v '^$' || true
        return
    fi
    _yaml_host_block "${host}" | awk -v k="${key}" '
        $0 ~ "^    " k ":$" { p=1; next }
        p && /^      - / { gsub(/^      - /, ""); gsub(/"/, ""); print }
        p && /^    [a-z_]/ { exit }
    ' || true
}

_load_workflow_lists() {
    local host="${1:-mac}"
    GW_GPU_WORKFLOWS=()
    GW_CPU_WORKFLOWS=()
    while IFS= read -r wf; do
        [[ -n "${wf}" ]] && GW_GPU_WORKFLOWS+=("${wf}")
    done < <(_yaml_list "${host}" gpu_workflows)
    while IFS= read -r wf; do
        [[ -n "${wf}" ]] && GW_CPU_WORKFLOWS+=("${wf}")
    done < <(_yaml_list "${host}" cpu_workflows)
}

_is_gpu_workflow() {
    local wf="$1"
    local g
    for g in "${GW_GPU_WORKFLOWS[@]}"; do
        [[ "${g}" == "${wf}" ]] && return 0
    done
    return 1
}

_is_cpu_workflow() {
    local wf="$1"
    local c
    for c in "${GW_CPU_WORKFLOWS[@]}"; do
        [[ "${c}" == "${wf}" ]] && return 0
    done
    return 1
}

# ── Auto-detection ───────────────────────────────────────────────────────────

_detect_wsl() {
    [[ -n "${WSL_DISTRO_NAME:-}" ]] && return 0
    [[ -f /proc/version ]] && grep -qi microsoft /proc/version 2>/dev/null && return 0
    return 1
}

_detect_nvidia_gpu() {
    command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null && return 0
    if command -v podman &>/dev/null; then
        local out
        out=$(podman run --rm --privileged --gpus all docker.io/nvidia/cuda:12.0.1-base-ubuntu22.04 nvidia-smi 2>&1) || true
        echo "${out}" | grep -qE "NVIDIA-SMI|GeForce" && return 0
    fi
    return 1
}

_auto_detect_host() {
    if _detect_wsl; then
        echo wsl
        return
    fi
    case "$(uname -s)" in
        Darwin)
            echo mac
            return
            ;;
        Linux)
            if command -v podman &>/dev/null && _detect_nvidia_gpu; then
                echo bazzite
                return
            fi
            # Linux without GPU: behave like WSL (light tests)
            echo wsl
            return
            ;;
    esac
    echo wsl
}

# ── Public API ───────────────────────────────────────────────────────────────

resolve_test_host() {
    local requested="${1:-auto}"
    local host=""

    if [[ -f "${GW_TEST_HOST_LOCAL}" ]]; then
        # shellcheck source=/dev/null
        source "${GW_TEST_HOST_LOCAL}"
    fi

    if [[ -n "${GW_TEST_HOST:-}" ]]; then
        host="${GW_TEST_HOST}"
    elif [[ "${requested}" != "auto" ]]; then
        host="${requested}"
    else
        host="$(_auto_detect_host)"
    fi

    case "${host}" in
        wsl|mac|bazzite) ;;
        *)
            echo "ERROR: unknown test host '${host}' (expected wsl, mac, or bazzite)" >&2
            return 1
            ;;
    esac

    if [[ ! -f "${GW_TEST_HOSTS_YAML}" ]]; then
        echo "ERROR: missing ${GW_TEST_HOSTS_YAML}" >&2
        return 1
    fi

    GW_RESOLVED_HOST="${host}"
    _load_workflow_lists "${host}"
    export GW_RESOLVED_HOST
}

host_default_tier() {
    local host="${1:-${GW_RESOLVED_HOST}}"
    _yaml_scalar "${host}" default_tier
}

host_real_allowed() {
    local host="${1:-${GW_RESOLVED_HOST}}"
    [[ "$(_yaml_scalar "${host}" real_allowed)" == "true" ]]
}

host_real_profile() {
    local host="${1:-${GW_RESOLVED_HOST}}"
    _yaml_scalar "${host}" real_profile
}

host_stub_profile() {
    local host="${1:-${GW_RESOLVED_HOST}}"
    local p
    p=$(_yaml_scalar "${host}" stub_profile)
    echo "${p:-test}"
}

host_integration_stub_args() {
    local host="${1:-${GW_RESOLVED_HOST}}"
    _yaml_list "${host}" integration_stub_args
}

# Returns 0 if workflow should run in real mode on this host; 1 if skip
workflow_real_allowed() {
    local host="${1:-${GW_RESOLVED_HOST}}"
    local wf="$2"
    local tier_real="${3:-false}"

    if [[ "${tier_real}" != "true" ]]; then
        return 0
    fi

    if ! host_real_allowed "${host}"; then
        return 1
    fi

    case "${host}" in
        mac)
            _is_cpu_workflow "${wf}"
            ;;
        bazzite)
            return 0
            ;;
        wsl)
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# Returns 0 if workflow needs --scmodal_use_cpu true on stub-run (integration only)
workflow_needs_cpu_stub() {
    local wf="$2"
    [[ "${wf}" == "integration" ]]
}

host_has_requirement() {
    local host="${1:-${GW_RESOLVED_HOST}}"
    local req="$2"
    local r
    while IFS= read -r r; do
        [[ "${r}" == "${req}" ]] && return 0
    done < <(_yaml_list "${host}" requires)
    return 1
}

check_host_requirements() {
    local host="${1:-${GW_RESOLVED_HOST}}"
    local missing=0

    if host_has_requirement "${host}" nextflow; then
        command -v nextflow &>/dev/null || { echo "missing: nextflow" >&2; missing=1; }
    fi
    if host_has_requirement "${host}" podman; then
        command -v podman &>/dev/null || { echo "missing: podman" >&2; missing=1; }
    fi
    if host_has_requirement "${host}" nvidia_gpu; then
        _detect_nvidia_gpu || { echo "missing: nvidia_gpu" >&2; missing=1; }
    fi
    return "${missing}"
}

resolve_tier() {
    local host="${1:-${GW_RESOLVED_HOST}}"
    local requested="${2:-auto}"
    if [[ "${requested}" == "auto" ]]; then
        host_default_tier "${host}"
    else
        echo "${requested}"
    fi
}

tier_is_stub_or_real() {
    local tier="$1"
    [[ "${tier}" == "stub" || "${tier}" == "real" ]]
}
