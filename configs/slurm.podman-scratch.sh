podman_scratch_requested() {
    local value

    for value in \
        "${NXF_PODMAN_REQUIRE_LOCAL_SCRATCH:-}" \
        "${SLURM_STEP_GRES:-}" \
        "${SLURM_JOB_GRES:-}" \
        "${GRES:-}" \
        "${SBATCH_GRES:-}"
    do
        [[ -z "${value}" ]] && continue
        case "${value}" in
            1|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|[Oo][Nn])
                return 0
                ;;
            *[Dd][Ii][Ss][Kk]:*)
                return 0
                ;;
        esac
    done

    return 1
}

podman_fs_type() {
    local path="$1"
    local fs_type=''

    if command -v findmnt >/dev/null 2>&1; then
        fs_type="$(findmnt -no FSTYPE -T "${path}" 2>/dev/null || true)"
    fi
    if [[ -z "${fs_type}" ]]; then
        fs_type="$(stat -f -c %T "${path}" 2>/dev/null || true)"
    fi
    if [[ -z "${fs_type}" ]]; then
        fs_type="$(stat -f %T "${path}" 2>/dev/null || true)"
    fi

    printf '%s' "${fs_type:-unknown}"
}

podman_fs_is_network() {
    case "$1" in
        nfs|nfs4|lustre|gpfs|panfs|beegfs|cifs|smbfs|sshfs|fuse.sshfs|ceph|ceph-fuse|glusterfs|afs|autofs)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

podman_existing_ancestor() {
    local path="$1"

    while [[ ! -e "${path}" && "${path}" != "/" ]]; do
        path="$(dirname "${path}")"
    done

    printf '%s' "${path:-/}"
}

podman_emit_primary_candidate_paths() {
    local job_token user_token root
    local old_ifs

    job_token="${SLURM_JOB_ID:-$$}"
    user_token="${USER:-user}"

    if [[ -n "${NXF_PODMAN_TMPDIR:-}" ]]; then
        printf '%s\n' "${NXF_PODMAN_TMPDIR}"
        return 0
    fi

    if [[ -n "${NXF_PODMAN_LOCAL_ROOTS:-}" ]]; then
        old_ifs="${IFS}"
        IFS=':'
        for root in ${NXF_PODMAN_LOCAL_ROOTS}; do
            [[ -n "${root}" ]] || continue
            printf '%s\n' "${root%/}/nextflow-podman/${user_token}/job-${job_token}"
            printf '%s\n' "${root%/}/${user_token}/job-${job_token}"
            printf '%s\n' "${root%/}/job-${job_token}"
        done
        IFS="${old_ifs}"
    fi

    for root in "${SLURM_TMPDIR:-}" "${TMPDIR:-}" "/mnt/lscratch" "/lscratch" "/scratch" "/local_scratch" "/local"; do
        [[ -n "${root}" ]] || continue
        printf '%s\n' "${root%/}/nextflow-podman/${user_token}/job-${job_token}"
        printf '%s\n' "${root%/}/${user_token}/job-${job_token}"
        printf '%s\n' "${root%/}/job-${job_token}"
    done

    if command -v findmnt >/dev/null 2>&1; then
        findmnt -rn -o TARGET,FSTYPE 2>/dev/null | while read -r root fs_type; do
            case "${root}" in
                /mnt/*|/scratch*|/local*|/var/tmp|/tmp)
                    if podman_fs_is_network "${fs_type}"; then
                        continue
                    fi
                    printf '%s\n' "${root%/}/nextflow-podman/${user_token}/job-${job_token}"
                    printf '%s\n' "${root%/}/${user_token}/job-${job_token}"
                    printf '%s\n' "${root%/}/job-${job_token}"
                    ;;
            esac
        done
    fi
}

podman_emit_fallback_candidate_paths() {
    local job_token user_token root

    job_token="${SLURM_JOB_ID:-$$}"
    user_token="${USER:-user}"

    for root in "/var/tmp" "/tmp"; do
        printf '%s\n' "${root%/}/nextflow-podman/${user_token}/job-${job_token}"
        printf '%s\n' "${root%/}/${user_token}/job-${job_token}"
        printf '%s\n' "${root%/}/job-${job_token}"
    done
}

podman_candidate_is_usable() {
    local candidate="$1"
    local ancestor fs_type

    ancestor="$(podman_existing_ancestor "${candidate}")"
    fs_type="$(podman_fs_type "${ancestor}")"
    [[ "${fs_type}" != 'unknown' ]] || return 1
    podman_fs_is_network "${fs_type}" && return 1
    mkdir -p "${candidate}" 2>/dev/null || return 1
    return 0
}

podman_resolve_tmp_base() {
    local candidate

    PODMAN_TMP_BASE=''
    PODMAN_TMP_BASE_AUTOCREATED=0

    if [[ -n "${NXF_PODMAN_TMPDIR:-}" ]]; then
        if podman_candidate_is_usable "${NXF_PODMAN_TMPDIR}"; then
            PODMAN_TMP_BASE="${NXF_PODMAN_TMPDIR}"
            return 0
        fi
        echo "[PODMAN_ERROR] NXF_PODMAN_TMPDIR is not a writable local filesystem: ${NXF_PODMAN_TMPDIR}" >&2
        return 92
    fi

    while IFS= read -r candidate; do
        [[ -n "${candidate}" ]] || continue
        if podman_candidate_is_usable "${candidate}"; then
            PODMAN_TMP_BASE="${candidate}"
            PODMAN_TMP_BASE_AUTOCREATED=1
            return 0
        fi
    done < <(podman_emit_primary_candidate_paths)

    if podman_scratch_requested; then
        echo "[PODMAN_ERROR] disk GRES was requested, but no usable scratch-like local filesystem candidate was found." >&2
        echo "[PODMAN_ERROR] Set NXF_PODMAN_TMPDIR to a node-local path or provide roots in NXF_PODMAN_LOCAL_ROOTS." >&2
        return 92
    fi

    while IFS= read -r candidate; do
        [[ -n "${candidate}" ]] || continue
        if podman_candidate_is_usable "${candidate}"; then
            PODMAN_TMP_BASE="${candidate}"
            PODMAN_TMP_BASE_AUTOCREATED=1
            return 0
        fi
    done < <(podman_emit_fallback_candidate_paths)

    echo "[PODMAN_ERROR] Unable to resolve a writable local scratch directory for podman overlay storage." >&2
    echo "[PODMAN_ERROR] Set NXF_PODMAN_TMPDIR to a node-local path or provide roots in NXF_PODMAN_LOCAL_ROOTS." >&2
    return 92
}