nxf_podman_fs_type() {
    local path="$1"
    local fs_type=""

    if command -v stat >/dev/null 2>&1; then
        fs_type="$(stat -f -c %T "${path}" 2>/dev/null || true)"
    fi

    if [[ -z "${fs_type}" ]] && command -v findmnt >/dev/null 2>&1; then
        fs_type="$(findmnt -n -o FSTYPE -T "${path}" 2>/dev/null | head -n 1 || true)"
    fi

    if [[ -z "${fs_type}" ]] && command -v df >/dev/null 2>&1; then
        fs_type="$(df -PT "${path}" 2>/dev/null | awk 'NR==2 {print $2}' || true)"
    fi

    printf '%s' "${fs_type:-unknown}"
}

nxf_podman_is_remote_fs_type() {
    case "$1" in
        nfs|nfs4|lustre|gpfs|beegfs|cifs|smb2|smbfs|panfs|ceph|cephfs|sshfs|fuse.sshfs|fuse.ceph|gcsfuse|davfs|orangefs|moosefs)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

nxf_podman_validate_local_scratch_candidate() {
    local candidate="$1"
    local resolved fs_type

    [[ -n "${candidate}" ]] || return 1
    candidate="${candidate%/}"
    mkdir -p "${candidate}" 2>/dev/null || true

    if [[ ! -d "${candidate}" || ! -w "${candidate}" ]]; then
        echo "[PODMAN_DIAG] rejecting local scratch candidate=${candidate} reason=not-writable" >&2
        return 1
    fi

    resolved="$(cd "${candidate}" 2>/dev/null && pwd -P)"
    if [[ -z "${resolved}" ]]; then
        echo "[PODMAN_DIAG] rejecting local scratch candidate=${candidate} reason=unresolvable" >&2
        return 1
    fi

    fs_type="$(nxf_podman_fs_type "${resolved}")"

    case "${resolved}" in
        /home/exacloud/gscratch/*|/gscratch/*)
            echo "[PODMAN_DIAG] rejecting local scratch candidate=${resolved} fs_type=${fs_type} reason=gscratch" >&2
            return 1
            ;;
    esac

    if nxf_podman_is_remote_fs_type "${fs_type}"; then
        echo "[PODMAN_DIAG] rejecting local scratch candidate=${resolved} fs_type=${fs_type} reason=remote-fs" >&2
        return 1
    fi

    printf '%s' "${resolved}"
}

nxf_podman_local_scratch_candidates() {
    local user_name

    user_name="${USER:-$(id -un 2>/dev/null || echo user)}"

    printf '%s\n' \
        "${NXF_PODMAN_LOCAL_SCRATCH:-}" \
        "${SLURM_TMPDIR:-}" \
        "${TMPDIR:-}" \
        "/scratch/${user_name}" \
        "/scratch" \
        "/localscratch/${user_name}" \
        "/localscratch" \
        "/local/${user_name}" \
        "/local" \
        "/lscratch/${user_name}" \
        "/lscratch" \
        "/tmp" \
        "/var/tmp"
}

nxf_resolve_podman_local_scratch() {
    local candidate resolved

    while IFS= read -r candidate; do
        [[ -n "${candidate}" ]] || continue
        if resolved="$(nxf_podman_validate_local_scratch_candidate "${candidate}")"; then
            printf '%s' "${resolved}"
            return 0
        fi
    done < <(nxf_podman_local_scratch_candidates)

    echo "ERROR: Could not find writable node-local scratch for rootless Podman graphRoot." >&2
    echo "Set NXF_PODMAN_LOCAL_SCRATCH to a node-local path, or ensure SLURM/TMPDIR local scratch is available." >&2
    return 1
}

nxf_current_podman_job_storage() {
    local candidate

    if [[ -n "${CONTAINERS_STORAGE_CONF:-}" ]]; then
        candidate="$(dirname "${CONTAINERS_STORAGE_CONF}")"
        if [[ -d "${candidate}" ]]; then
            printf '%s' "${candidate}"
            return 0
        fi
    fi

    if [[ -n "${CONTAINERS_RUNROOT:-}" ]]; then
        candidate="$(dirname "${CONTAINERS_RUNROOT%/}")"
        if [[ -d "${candidate}" ]]; then
            printf '%s' "${candidate}"
            return 0
        fi
    fi

    if [[ -n "${TMPDIR:-}" ]]; then
        candidate="$(dirname "${TMPDIR%/}")"
        if [[ "${candidate}" == */goodworkflows-podman/* ]]; then
            printf '%s' "${candidate}"
            return 0
        fi
    fi

    if candidate="$(nxf_resolve_podman_local_scratch 2>/dev/null)"; then
        printf '%s' "${candidate%/}/goodworkflows-podman/${SLURM_JOB_ID:-$$}"
        return 0
    fi

    return 1
}