set -euo pipefail

resolve_podman_local_scratch() {
    local candidate

    for candidate in "${NXF_PODMAN_LOCAL_SCRATCH:-}" "${SLURM_TMPDIR:-}"; do
        [[ -n "${candidate}" ]] || continue
        mkdir -p "${candidate}" 2>/dev/null || true
        if [[ -d "${candidate}" && -w "${candidate}" ]]; then
            printf '%s' "${candidate}"
            return 0
        fi
    done

    echo "ERROR: Rootless Podman graphRoot cannot live on gscratch/NFS." >&2
    echo "Set NXF_PODMAN_LOCAL_SCRATCH to node-local disk or request SLURM local disk so SLURM_TMPDIR is available." >&2
    return 1
}

podman_cache_key() {
    printf '%s' "$1" | tr '/:@' '___' | tr -cd '[:alnum:]_.-'
}

configure_podman_storage() {
    local local_scratch_root fuse_overlayfs_bin

    local_scratch_root="$(resolve_podman_local_scratch)"
    JOB_STORAGE="${local_scratch_root%/}/goodworkflows-podman/${SLURM_JOB_ID:-$$}"
    export CONTAINERS_RUNROOT="${JOB_STORAGE}/run"
    export TMPDIR="${JOB_STORAGE}/tmp"
    export XDG_RUNTIME_DIR="${JOB_STORAGE}/xdg-${UID}"
    export NXF_PODMAN_CACHEDIR="${NXF_PODMAN_CACHEDIR:-${NXF_WORK:-.}/.podman-oci-cache}"
    export CONTAINERS_STORAGE_CONF="${JOB_STORAGE}/storage.conf"

    mkdir -p "${JOB_STORAGE}/storage" "${CONTAINERS_RUNROOT}" "${TMPDIR}" "${XDG_RUNTIME_DIR}" "${NXF_PODMAN_CACHEDIR}"
    chmod 0700 "${XDG_RUNTIME_DIR}"

    fuse_overlayfs_bin="$(command -v fuse-overlayfs || true)"
    {
        printf '[storage]\n'
        printf 'driver = "overlay"\n'
        printf 'graphroot = "%s"\n' "${JOB_STORAGE}/storage"
        printf 'runroot = "%s"\n\n' "${CONTAINERS_RUNROOT}"
        printf '[storage.options]\n'
        printf 'additionalimagestores = []\n\n'
        printf '[storage.options.overlay]\n'
        if [[ -n "${fuse_overlayfs_bin}" ]]; then
            printf 'mount_program = "%s"\n' "${fuse_overlayfs_bin}"
        fi
    } > "${CONTAINERS_STORAGE_CONF}"

    PULL_LOCK_BASE="${NXF_PODMAN_PULL_LOCK_DIR:-${NXF_WORK:-.}/.podman-pull-locks}"
    mkdir -p "${PULL_LOCK_BASE}"

    echo "[PODMAN_DIAG] local_scratch_root=${local_scratch_root}"
    echo "[PODMAN_DIAG] job_storage=${JOB_STORAGE}"
    echo "[PODMAN_DIAG] containers_storage_conf=${CONTAINERS_STORAGE_CONF}"
    echo "[PODMAN_DIAG] containers_runroot=${CONTAINERS_RUNROOT}"
    echo "[PODMAN_DIAG] tmpdir=${TMPDIR}"
    echo "[PODMAN_DIAG] oci_cache=${NXF_PODMAN_CACHEDIR}"
    echo "[PODMAN_DIAG] pull_lock_base=${PULL_LOCK_BASE}"
    df -h "${JOB_STORAGE}" || true
    df -i "${JOB_STORAGE}" || true
}

if command -v module &>/dev/null; then
    module load podman 2>/dev/null \
        || echo "Warning: 'module load podman' failed - continuing"
fi

configure_podman_storage

cleanup_stale_locks() {
    find "${PULL_LOCK_BASE}" -maxdepth 1 -type f -name '*.lock' -mmin +120 -delete 2>/dev/null || true
    find "${PULL_LOCK_BASE}" -maxdepth 1 -type d -name '*.lock.d' -mmin +120 -exec rm -rf {} + 2>/dev/null || true
}

podman_pull_once() {
    local image="$1"

    if command -v timeout &>/dev/null; then
        timeout 3600 podman pull "${image}"
    else
        podman pull "${image}"
    fi
}

load_from_oci_cache() {
    local image="$1"
    local key archive

    key="$(podman_cache_key "${image}")"
    archive="${NXF_PODMAN_CACHEDIR}/${key}.tar"
    [[ -f "${archive}.done" ]] || return 1

    echo "[CACHE] Loading OCI archive: ${archive}"
    if podman load -i "${archive}" >/dev/null; then
        return 0
    fi

    echo "[WARN] Failed to load OCI archive for ${image}; removing done sentinel and falling back to registry pull" >&2
    rm -f "${archive}.done"
    return 1
}

export_oci_archive() {
    local image="$1"
    local key archive

    key="$(podman_cache_key "${image}")"
    archive="${NXF_PODMAN_CACHEDIR}/${key}.tar"

    if [[ -f "${archive}.done" ]]; then
        return 0
    fi

    echo "[CACHE] Saving OCI archive: ${archive}"
    if podman save --format oci-archive -o "${archive}.tmp" "${image}" >/dev/null; then
        mv "${archive}.tmp" "${archive}"
        touch "${archive}.done"
        return 0
    fi

    echo "[WARN] Failed to save OCI archive for ${image}" >&2
    rm -f "${archive}.tmp"
    return 1
}

# Best-effort image pre-pull with lock to avoid N-way concurrent pulls of
# the same image. If the image cannot be determined, continue and let
# Nextflow/podman handle the pull during container launch.
get_task_image() {
    local v=''
    for name in NXF_TASK_CONTAINER NXF_CONTAINER NXF_CONTAINER_IMAGE NXF_CONTAINER_NAME; do
        eval "v=\${${name}:-}"
        if [[ -n "${v}" ]]; then
            printf '%s' "${v}"
            return 0
        fi
    done

    if [[ -f .command.run ]]; then
        v="$(awk '
            /podman run/ {
                for (i=1; i<=NF; i++) {
                    if ($i ~ /^[[:alnum:]][[:alnum:]_.\/-]*:[[:alnum:]_.-]+$/) {
                        print $i
                        exit
                    }
                }
            }
        ' .command.run)"
        if [[ -n "${v}" ]]; then
            printf '%s' "${v}"
            return 0
        fi
    fi

    return 1
}

pull_with_lock() {
    local image="$1"
    local key lock_file lock_dir attempt wait_s lock_fd status
    key="$(podman_cache_key "${image}")"
    lock_file="${PULL_LOCK_BASE}/${key}.lock"
    lock_dir="${lock_file}.d"
    status=1

    if command -v flock &>/dev/null; then
        exec {lock_fd}>"${lock_file}"
        flock "${lock_fd}"
        if podman image exists "${image}" 2>/dev/null; then
            echo "[SKIP] Image already present in local task storage: ${image}"
            export_oci_archive "${image}" || true
            status=0
        elif load_from_oci_cache "${image}"; then
            echo "[OK] Loaded ${image} from OCI archive cache"
            status=0
        else
            for attempt in 1 2 3; do
                if podman_pull_once "${image}"; then
                    echo "[OK] Pulled ${image} from registry"
                    export_oci_archive "${image}" || true
                    status=0
                    break
                fi
                wait_s=$(( (2 ** attempt) * 10 + RANDOM % 10 ))
                echo "[RETRY] Pull failed (attempt ${attempt}) for ${image}; retrying in ${wait_s}s"
                sleep "${wait_s}"
            done
        fi
        flock -u "${lock_fd}"
        exec {lock_fd}>&-
        rm -f "${lock_file}"
        return "${status}"
    fi

    until mkdir "${lock_dir}" 2>/dev/null; do
        sleep $((2 + RANDOM % 4))
    done

    if podman image exists "${image}" 2>/dev/null; then
        echo "[SKIP] Image already present in local task storage: ${image}"
        export_oci_archive "${image}" || true
        status=0
    elif load_from_oci_cache "${image}"; then
        echo "[OK] Loaded ${image} from OCI archive cache"
        status=0
    else
        for attempt in 1 2 3; do
            if podman_pull_once "${image}"; then
                echo "[OK] Pulled ${image} from registry"
                export_oci_archive "${image}" || true
                status=0
                break
            fi
            wait_s=$(( (2 ** attempt) * 10 + RANDOM % 10 ))
            echo "[RETRY] Pull failed (attempt ${attempt}) for ${image}; retrying in ${wait_s}s"
            sleep "${wait_s}"
        done
    fi

    rmdir "${lock_dir}" 2>/dev/null || true
    return "${status}"
}

if command -v podman &>/dev/null; then
    cleanup_stale_locks
    if task_image="$(get_task_image)"; then
        pull_with_lock "${task_image}" || true
    fi
fi

# Rootless Podman on exacloud does not get delegated cpu/cpuset controllers.
# Nextflow still emits podman cpu/memory resource flags from task directives,
# but SLURM already enforces those limits for the job allocation.
nxf_rootless_podman_filter_run_args() {
    local arg
    NXF_PODMAN_FILTERED_ARGS=()

    while (($#)); do
        arg="$1"
        shift
        case "$arg" in
            --cpu-shares|-c|--memory|-m|--memory-swap|--memory-reservation|--cpus|--cpu-period|--cpu-quota|--cpuset-cpus|--cpuset-mems)
                (($#)) && shift
                ;;
            --cpu-shares=*|-c=*|--memory=*|-m=*|--memory-swap=*|--memory-reservation=*|--cpus=*|--cpu-period=*|--cpu-quota=*|--cpuset-cpus=*|--cpuset-mems=*)
                ;;
            *)
                NXF_PODMAN_FILTERED_ARGS+=("$arg")
                ;;
        esac
    done
}

podman() {
    if [[ "${1:-}" == "run" ]] && [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        shift
        nxf_rootless_podman_filter_run_args "$@"
        echo "[PODMAN_DIAG] rootless podman run: stripping cpu/memory cgroup flags; SLURM enforces task resources" >&2
        command podman run "${NXF_PODMAN_FILTERED_ARGS[@]}"
        return $?
    fi

    command podman "$@"
}