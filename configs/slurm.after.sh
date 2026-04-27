set -euo pipefail

if podman_resolve_tmp_base 2>/dev/null; then
    :
else
    PODMAN_TMP_BASE="${NXF_PODMAN_TMPDIR:-}"
    PODMAN_TMP_BASE_AUTOCREATED=0
fi

[[ -n "${PODMAN_TMP_BASE:-}" ]] || exit 0

LOCAL_PODMAN_ROOT="${PODMAN_TMP_BASE}/podman"
XDG_RUNTIME_DIR="${PODMAN_TMP_BASE}/runtime-${UID}"

rm -rf "${LOCAL_PODMAN_ROOT}" "${XDG_RUNTIME_DIR}"

if [[ "${PODMAN_TMP_BASE_AUTOCREATED:-0}" == "1" ]]; then
    rm -rf "${PODMAN_TMP_BASE}"
fi