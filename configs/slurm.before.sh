set -euo pipefail

# Per-task ephemeral scratch: lock files, run state, and TMPDIR live under
# NXF_WORK on gscratch, scoped to this SLURM job. Podman graphRoot (image
# layers) comes from ~/.config/containers/storage.conf — do NOT override it.
# force_mask="0700" in storage.conf is required so Podman does not attempt
# lsetxattr on the NFS-backed gscratch filesystem.
JOB_STORAGE="${NXF_WORK:-.}/.podman-scratch/${SLURM_JOB_ID:-$$}"
export CONTAINERS_RUNROOT="${JOB_STORAGE}/run"
export TMPDIR="${JOB_STORAGE}/tmp"
export XDG_RUNTIME_DIR="${JOB_STORAGE}/xdg-${UID}"
mkdir -p "${CONTAINERS_RUNROOT}" "${TMPDIR}" "${XDG_RUNTIME_DIR}"
chmod 0700 "${XDG_RUNTIME_DIR}"

# Shared lock directory (on NFS so locks are cluster-wide).
PULL_LOCK_BASE="${NXF_PODMAN_PULL_LOCK_DIR:-${NXF_WORK:-.}/.podman-pull-locks}"
mkdir -p "${PULL_LOCK_BASE}"

# Lightweight diagnostics.
echo "[PODMAN_DIAG] job_storage=${JOB_STORAGE}"
echo "[PODMAN_DIAG] containers_runroot=${CONTAINERS_RUNROOT}"
echo "[PODMAN_DIAG] tmpdir=${TMPDIR}"
echo "[PODMAN_DIAG] pull_lock_base=${PULL_LOCK_BASE}"
df -h "${JOB_STORAGE}" || true
df -i "${JOB_STORAGE}" || true

if command -v module &>/dev/null; then
    module load podman 2>/dev/null \
        || echo "Warning: 'module load podman' failed - continuing"
fi

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