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

# Detect the user's existing Podman graphRoot (typically the NFS-backed image store).
# Returns $NXF_PODMAN_GRAPHROOT if already set, else queries `podman info`,
# else errors asking the user to set the variable explicitly.
nxf_podman_detect_graphroot() {
    if [[ -n "${NXF_PODMAN_GRAPHROOT:-}" ]]; then
        printf '%s' "${NXF_PODMAN_GRAPHROOT}"
        return 0
    fi

    local gr
    gr="$(command podman info --format '{{.Store.GraphRoot}}' 2>/dev/null || true)"
    if [[ -n "${gr}" ]]; then
        printf '%s' "${gr}"
        return 0
    fi

    echo "ERROR: Cannot detect Podman graphRoot. Set NXF_PODMAN_GRAPHROOT to the path of your existing image store (e.g. export NXF_PODMAN_GRAPHROOT=/home/exacloud/gscratch/.../dockerContainers)." >&2
    return 1
}

# Storage configuration for the pre-pull job.
#   graphroot           -> NFS-backed user image store (images land here; already present = fast no-op)
#   runroot / tmp / xdg -> node-local scratch (lock files and transient runtime state only)
configure_prepull_storage() {
    local local_scratch_root fuse_overlayfs_bin graphroot

    graphroot="$(nxf_podman_detect_graphroot)"
    export NXF_PODMAN_GRAPHROOT="${graphroot}"

    local_scratch_root="$(nxf_resolve_podman_local_scratch)"
    JOB_STORAGE="${local_scratch_root%/}/goodworkflows-podman/${SLURM_JOB_ID:-$$}"
    export CONTAINERS_RUNROOT="${JOB_STORAGE}/run"
    export TMPDIR="${JOB_STORAGE}/tmp"
    export XDG_RUNTIME_DIR="${JOB_STORAGE}/xdg-${UID}"
    export CONTAINERS_STORAGE_CONF="${JOB_STORAGE}/storage.conf"
    export NXF_PODMAN_PULL_LOCK_DIR="${NXF_PODMAN_PULL_LOCK_DIR:-${NXF_WORK_ROOT:-${PWD}/work}/.podman-pull-locks}"

    mkdir -p "${JOB_STORAGE}" "${CONTAINERS_RUNROOT}" "${TMPDIR}" "${XDG_RUNTIME_DIR}" \
             "${NXF_PODMAN_PULL_LOCK_DIR}" "${PWD}/logs" 2>/dev/null || true
    chmod 0700 "${XDG_RUNTIME_DIR}"

    fuse_overlayfs_bin="$(command -v fuse-overlayfs || true)"
    {
        printf '[storage]\n'
        printf 'driver = "overlay"\n'
        printf 'graphroot = "%s"\n' "${graphroot}"
        printf 'runroot = "%s"\n\n' "${CONTAINERS_RUNROOT}"
        printf '[storage.options]\n'
        printf 'additionalimagestores = []\n\n'
        printf '[storage.options.overlay]\n'
        if [[ -n "${fuse_overlayfs_bin}" ]]; then
            printf 'mount_program = "%s"\n' "${fuse_overlayfs_bin}"
        fi
    } > "${CONTAINERS_STORAGE_CONF}"

    echo "[PODMAN_DIAG] mode=prepull"
    echo "[PODMAN_DIAG] graphroot=${graphroot}"
    echo "[PODMAN_DIAG] job_storage=${JOB_STORAGE}"
    echo "[PODMAN_DIAG] containers_storage_conf=${CONTAINERS_STORAGE_CONF}"
    echo "[PODMAN_DIAG] containers_runroot=${CONTAINERS_RUNROOT}"
    echo "[PODMAN_DIAG] tmpdir=${TMPDIR}"
    echo "[PODMAN_DIAG] pull_lock_dir=${NXF_PODMAN_PULL_LOCK_DIR}"
    df -h "${graphroot}" || true
    df -i "${graphroot}" || true
}

# Storage configuration for individual Nextflow task processes.
#   graphroot              -> node-local scratch (overlay upper-dirs only; small)
#   additionalimagestores  -> NFS-backed user image store (image layers served read-only from here)
#   runroot / tmp / xdg    -> node-local scratch
configure_task_storage() {
    local local_scratch_root fuse_overlayfs_bin graphroot

    graphroot="$(nxf_podman_detect_graphroot)"
    export NXF_PODMAN_GRAPHROOT="${graphroot}"

    local_scratch_root="$(nxf_resolve_podman_local_scratch)"
    JOB_STORAGE="${local_scratch_root%/}/goodworkflows-podman/${SLURM_JOB_ID:-$$}"
    export CONTAINERS_RUNROOT="${JOB_STORAGE}/run"
    export TMPDIR="${JOB_STORAGE}/tmp"
    export XDG_RUNTIME_DIR="${JOB_STORAGE}/xdg-${UID}"
    export CONTAINERS_STORAGE_CONF="${JOB_STORAGE}/storage.conf"

    mkdir -p "${JOB_STORAGE}/storage" "${CONTAINERS_RUNROOT}" "${TMPDIR}" "${XDG_RUNTIME_DIR}"
    chmod 0700 "${XDG_RUNTIME_DIR}"

    fuse_overlayfs_bin="$(command -v fuse-overlayfs || true)"
    {
        printf '[storage]\n'
        printf 'driver = "overlay"\n'
        printf 'graphroot = "%s"\n' "${JOB_STORAGE}/storage"
        printf 'runroot = "%s"\n\n' "${CONTAINERS_RUNROOT}"
        printf '[storage.options]\n'
        printf 'additionalimagestores = ["%s"]\n\n' "${graphroot}"
        printf '[storage.options.overlay]\n'
        if [[ -n "${fuse_overlayfs_bin}" ]]; then
            printf 'mount_program = "%s"\n' "${fuse_overlayfs_bin}"
        fi
    } > "${CONTAINERS_STORAGE_CONF}"

    echo "[PODMAN_DIAG] mode=task"
    echo "[PODMAN_DIAG] graphroot_local=${JOB_STORAGE}/storage"
    echo "[PODMAN_DIAG] additionalimagestores=${graphroot}"
    echo "[PODMAN_DIAG] job_storage=${JOB_STORAGE}"
    echo "[PODMAN_DIAG] containers_storage_conf=${CONTAINERS_STORAGE_CONF}"
    echo "[PODMAN_DIAG] containers_runroot=${CONTAINERS_RUNROOT}"
    echo "[PODMAN_DIAG] tmpdir=${TMPDIR}"
    df -h "${JOB_STORAGE}" || true
    df -i "${JOB_STORAGE}" || true
}