#!/usr/bin/env bash
# Lightweight regression test for the GoodWorkflows Podman storage contract.
#
# What this tests (no SLURM or real Podman required):
#   1. configure_prepull_storage generates a storage.conf where:
#        graphroot = the shared NFS store (NXF_PODMAN_GRAPHROOT), NOT local scratch
#        runroot   = inside node-local scratch (JOB_STORAGE/run)
#   2. configure_task_storage generates the same layout.
#   3. PODMAN_TMPDIR and TMPDIR are exported to node-local scratch.
#   4. XDG_RUNTIME_DIR is exported to node-local scratch and has mode 0700.
#   5. The resolver rejects gscratch and known remote filesystems for scratch.
#
# Usage:
#   bash tests/test_podman_storage.sh
#
# Exit 0 = all checks passed.  Exit 1 = at least one check failed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PODMAN_LOCAL_SH="${PIPELINE_ROOT}/configs/slurm.podman-local.sh"

PASS=0
FAIL=0

# Use temp files so pass/fail counts survive (...)  subshells.
_PASS_FILE=""
_FAIL_FILE=""

pass() {
    echo "  PASS: $1"
    [[ -n "${_PASS_FILE}" ]] && echo >> "${_PASS_FILE}"
    return 0
}
fail() {
    echo "  FAIL: $1"
    [[ -n "${_FAIL_FILE}" ]] && echo >> "${_FAIL_FILE}"
    return 0
}

check() {
    local label="$1" condition="$2"
    if eval "${condition}"; then
        pass "${label}"
    else
        fail "${label}"
    fi
}

_tally() {
    # Count lines written by pass/fail helpers and accumulate into PASS/FAIL.
    local p f
    p="$(wc -l < "${_PASS_FILE}" | tr -d ' ')"
    f="$(wc -l < "${_FAIL_FILE}" | tr -d ' ')"
    PASS=$(( PASS + p ))
    FAIL=$(( FAIL + f ))
    # Reset files for the next block.
    : > "${_PASS_FILE}"; : > "${_FAIL_FILE}"
}
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TEST_TMPDIR}"' EXIT

mkdir -p "${TEST_TMPDIR}/nfs-graphroot" "${TEST_TMPDIR}/local-scratch"
# Canonicalize both paths so comparisons work on macOS where /var/folders ->
# /private/var/folders via symlink, and nxf_podman_validate_local_scratch_candidate
# uses `pwd -P` to resolve the real path.
NFS_GRAPHROOT="$(cd "${TEST_TMPDIR}/nfs-graphroot" && pwd -P)"
LOCAL_SCRATCH="$(cd "${TEST_TMPDIR}/local-scratch" && pwd -P)"

export NXF_PODMAN_GRAPHROOT="${NFS_GRAPHROOT}"
export NXF_PODMAN_LOCAL_SCRATCH="${LOCAL_SCRATCH}"
# Provide a fake SLURM_JOB_ID so path construction is deterministic.
export SLURM_JOB_ID="99999"
# Prevent the helper from running real `podman info`.
export NXF_WORK_ROOT="${TEST_TMPDIR}/work"
mkdir -p "${NXF_WORK_ROOT}"

# Counter temp files (writable from subshells).
_PASS_FILE="${TEST_TMPDIR}/pass.log"
_FAIL_FILE="${TEST_TMPDIR}/fail.log"
export _PASS_FILE _FAIL_FILE
: > "${_PASS_FILE}"; : > "${_FAIL_FILE}"

echo "============================================================"
echo " GoodWorkflows Podman storage contract regression test"
echo "============================================================"
echo " PIPELINE_ROOT          : ${PIPELINE_ROOT}"
echo " NXF_PODMAN_GRAPHROOT   : ${NFS_GRAPHROOT}"
echo " NXF_PODMAN_LOCAL_SCRATCH: ${LOCAL_SCRATCH}"
echo "============================================================"

# ---------------------------------------------------------------------------
# Test 1: configure_prepull_storage
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 1: configure_prepull_storage ---"
(
    # Source in a subshell so exported vars do not bleed into Test 2.
    # shellcheck source=configs/slurm.podman-local.sh
    source "${PODMAN_LOCAL_SH}"
    configure_prepull_storage >/dev/null 2>&1 || true

    conf="${CONTAINERS_STORAGE_CONF}"
    runroot="${CONTAINERS_RUNROOT}"
    tmpdir="${TMPDIR}"
    podman_tmpdir="${PODMAN_TMPDIR:-}"
    xdg="${XDG_RUNTIME_DIR:-}"
    graphroot_in_conf="$(grep '^graphroot' "${conf}" | awk -F'"' '{print $2}')"
    runroot_in_conf="$(grep '^runroot' "${conf}" | awk -F'"' '{print $2}')"

    check "storage.conf exists" "[[ -f '${conf}' ]]"
    check "graphroot in storage.conf = NXF_PODMAN_GRAPHROOT (shared)" \
        "[[ '${graphroot_in_conf}' == '${NFS_GRAPHROOT}' ]]"
    check "graphroot in storage.conf is NOT under local scratch" \
        "[[ '${graphroot_in_conf}' != '${LOCAL_SCRATCH}'* ]]"
    check "runroot in storage.conf is under local scratch" \
        "[[ '${runroot_in_conf}' == '${LOCAL_SCRATCH}'* ]]"
    check "CONTAINERS_RUNROOT is under local scratch" \
        "[[ '${runroot}' == '${LOCAL_SCRATCH}'* ]]"
    check "TMPDIR is under local scratch" \
        "[[ '${tmpdir}' == '${LOCAL_SCRATCH}'* ]]"
    check "PODMAN_TMPDIR is exported and under local scratch" \
        "[[ -n '${podman_tmpdir}' && '${podman_tmpdir}' == '${LOCAL_SCRATCH}'* ]]"
    check "XDG_RUNTIME_DIR is exported and under local scratch" \
        "[[ -n '${xdg}' && '${xdg}' == '${LOCAL_SCRATCH}'* ]]"
    check "XDG_RUNTIME_DIR has mode 0700" \
        "[[ \$(stat -c '%a' '${xdg}' 2>/dev/null || stat -f '%Lp' '${xdg}' 2>/dev/null) == '700' ]]"
    check "graphroot and runroot are on different top-level paths" \
        "[[ '${graphroot_in_conf}' != '${runroot_in_conf}'* ]]"
) || true
_tally

# ---------------------------------------------------------------------------
# Test 2: configure_task_storage
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 2: configure_task_storage ---"
(
    source "${PODMAN_LOCAL_SH}"
    configure_task_storage >/dev/null 2>&1 || true

    conf="${CONTAINERS_STORAGE_CONF}"
    runroot="${CONTAINERS_RUNROOT}"
    tmpdir="${TMPDIR}"
    podman_tmpdir="${PODMAN_TMPDIR:-}"
    xdg="${XDG_RUNTIME_DIR:-}"
    graphroot_in_conf="$(grep '^graphroot' "${conf}" | awk -F'"' '{print $2}')"
    runroot_in_conf="$(grep '^runroot' "${conf}" | awk -F'"' '{print $2}')"

    check "storage.conf exists" "[[ -f '${conf}' ]]"
    check "graphroot in storage.conf = NXF_PODMAN_GRAPHROOT (shared)" \
        "[[ '${graphroot_in_conf}' == '${NFS_GRAPHROOT}' ]]"
    check "graphroot in storage.conf is NOT under local scratch" \
        "[[ '${graphroot_in_conf}' != '${LOCAL_SCRATCH}'* ]]"
    check "runroot in storage.conf is under local scratch" \
        "[[ '${runroot_in_conf}' == '${LOCAL_SCRATCH}'* ]]"
    check "CONTAINERS_RUNROOT is under local scratch" \
        "[[ '${runroot}' == '${LOCAL_SCRATCH}'* ]]"
    check "TMPDIR is under local scratch" \
        "[[ '${tmpdir}' == '${LOCAL_SCRATCH}'* ]]"
    check "PODMAN_TMPDIR is exported and under local scratch" \
        "[[ -n '${podman_tmpdir}' && '${podman_tmpdir}' == '${LOCAL_SCRATCH}'* ]]"
    check "XDG_RUNTIME_DIR is exported and under local scratch" \
        "[[ -n '${xdg}' && '${xdg}' == '${LOCAL_SCRATCH}'* ]]"
) || true
_tally

# ---------------------------------------------------------------------------
# Test 3: scratch resolver rejects gscratch and remote-fs candidates
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 3: scratch resolver rejection logic ---"
(
    source "${PODMAN_LOCAL_SH}"

    # gscratch paths must be rejected.
    if nxf_podman_validate_local_scratch_candidate "/home/exacloud/gscratch/fakelab" >/dev/null 2>&1; then
        fail "gscratch path should be rejected but was accepted"
    else
        pass "gscratch path correctly rejected"
    fi

    if nxf_podman_validate_local_scratch_candidate "/gscratch/fakelab" >/dev/null 2>&1; then
        fail "/gscratch path should be rejected but was accepted"
    else
        pass "/gscratch path correctly rejected"
    fi

    # A real writable local directory should be accepted.
    real_local="$(mktemp -d)"
    if resolved="$(nxf_podman_validate_local_scratch_candidate "${real_local}" 2>/dev/null)"; then
        check "real local dir accepted and resolved" "[[ -n '${resolved}' ]]"
    else
        fail "real local writable dir should be accepted but was rejected"
    fi
    rm -rf "${real_local}"
) || true
_tally

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo " Results: ${PASS} passed, ${FAIL} failed"
echo "============================================================"

[[ "${FAIL}" -eq 0 ]]
