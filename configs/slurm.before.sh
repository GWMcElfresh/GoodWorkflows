set -euo pipefail

# Overlay storage MUST be on a local filesystem. Lustre/NFS does not support
# the xattr/hardlink operations required by fuse-overlayfs. Use node-local /tmp
# (or SLURM_TMPDIR when --tmp=N was requested) as the podman scratch root.
PODMAN_TMP_BASE="${NXF_PODMAN_TMPDIR:-${SLURM_TMPDIR:-/tmp}}"

mkdir -p "${PODMAN_TMP_BASE}"

# Default NXF_PODMAN_CACHEDIR to the user's configured podman graphRoot.
# Runs before CONTAINERS_GRAPHROOT is overridden so podman info reads the
# user's real storage.conf. Each user gets their own archive store automatically.
if [[ -z "${NXF_PODMAN_CACHEDIR:-}" ]] && command -v podman &>/dev/null; then
    NXF_PODMAN_CACHEDIR="$(podman info --format '{{.Store.GraphRoot}}' 2>/dev/null || true)"
fi
export NXF_PODMAN_CACHEDIR="${NXF_PODMAN_CACHEDIR:-}"

# OCI archive store on the shared filesystem (plain tar files; no overlay on NFS).
# Pre-pull writes archives here; this hook loads from the archive if the image
# is not already in the node-local store.
PODMAN_OCI_CACHE="${NXF_PODMAN_CACHEDIR:-}"

# Shared lock directory (on NFS so locks are cluster-wide).
PULL_LOCK_BASE="${NXF_PODMAN_PULL_LOCK_DIR:-${NXF_WORK:-${PWD}/.podman-pull-locks}}"
mkdir -p "${PULL_LOCK_BASE}"

# Lightweight diagnostics.
echo "[PODMAN_DIAG] tmp_base=${PODMAN_TMP_BASE}"
echo "[PODMAN_DIAG] pull_lock_base=${PULL_LOCK_BASE}"
echo "[PODMAN_DIAG] oci_cache=${PODMAN_OCI_CACHE:-not set}"
df -h "${PODMAN_TMP_BASE}" || true
df -i "${PODMAN_TMP_BASE}" || true

LOCAL_PODMAN_ROOT="${PODMAN_TMP_BASE}/podman-${SLURM_JOB_ID:-$$}"
export CONTAINERS_GRAPHROOT="${LOCAL_PODMAN_ROOT}/storage"

export CONTAINERS_RUNROOT="${LOCAL_PODMAN_ROOT}/run"
mkdir -p "${CONTAINERS_GRAPHROOT}" "${CONTAINERS_RUNROOT}"

export CONTAINERS_STORAGE_CONF="${LOCAL_PODMAN_ROOT}/storage.conf"
{
    printf '[storage]\n'
    printf 'driver = "overlay"\n'
    printf 'graphRoot = "%s"\n' "${CONTAINERS_GRAPHROOT}"
    printf 'runRoot   = "%s"\n\n' "${CONTAINERS_RUNROOT}"
    # Only emit overlay section if fuse-overlayfs is available on this node.
    if [[ -x "/usr/bin/fuse-overlayfs" ]]; then
        printf '[storage.options.overlay]\n'
        printf 'mount_program = "/usr/bin/fuse-overlayfs"\n'
    fi
} > "${CONTAINERS_STORAGE_CONF}"

mkdir -p "${XDG_RUNTIME_DIR}"
chmod 0700 "${XDG_RUNTIME_DIR}"

if command -v module &>/dev/null; then
    module load podman 2>/dev/null \
        || echo "Warning: 'module load podman' failed - continuing"
fi

# Load a pre-pulled image from the shared OCI archive cache (NFS-safe: plain
# tar reads). Called before falling back to a live registry pull.
load_from_oci_cache() {
    local image="$1"
    local key archive
    [[ -z "${PODMAN_OCI_CACHE:-}" || -z "${NXF_PODMAN_CACHEDIR:-}" ]] && return 1

    key="$(printf '%s' "${image}" | tr '/:@' '___' | tr -cd '[:alnum:]_.-')"
    archive="${PODMAN_OCI_CACHE}/${key}.tar"

    if [[ -f "${archive}.done" && -f "${archive}" ]]; then
        echo "[CACHE] Loading ${image} from OCI archive"
        if podman load -i "${archive}"; then
            echo "[OK] Loaded ${image} from cache"
            return 0
        else
            echo "[WARN] OCI archive load failed for ${image}; falling back to registry pull"
            return 1
        fi
    fi
    return 1
}

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

    # Fallback: parse image token from generated task wrapper.
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
    key="$(printf '%s' "${image}" | tr '/:@' '___' | tr -cd '[:alnum:]_.-')"
    lock_file="${PULL_LOCK_BASE}/${key}.lock"
    lock_dir="${lock_file}.d"
    status=1

    if command -v flock &>/dev/null; then
        exec {lock_fd}>"${lock_file}"
        flock "${lock_fd}"
        if podman image exists "${image}" 2>/dev/null; then
            echo "[SKIP] Image already present: ${image}"
            status=0
        elif load_from_oci_cache "${image}"; then
            status=0
        else
            for attempt in 1 2 3; do
                if podman_pull_once "${image}"; then
                    echo "[OK] Pulled ${image}"
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
        echo "[SKIP] Image already present: ${image}"
        status=0
    elif load_from_oci_cache "${image}"; then
        status=0
    else
        for attempt in 1 2 3; do
            if podman_pull_once "${image}"; then
                echo "[OK] Pulled ${image}"
                status=0
                break
            fi
            wait_s=$(( (2 ** attempt) * 10 + RANDOM % 10 ))
            echo "Podman pull failed (attempt ${attempt}) for ${image}; retrying in ${wait_s}s"
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