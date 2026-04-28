set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=configs/slurm.podman-local.sh
source "${SCRIPT_DIR}/slurm.podman-local.sh"

if command -v module &>/dev/null; then
    module load podman 2>/dev/null \
        || echo "Warning: 'module load podman' failed - continuing"
fi

# Configure per-task Podman storage:
#   graphroot  -> NFS-backed user image store (images already present after pre-pull)
#   runroot    -> node-local scratch (container runtime state only; small)
# CONTAINERS_STORAGE_CONF is exported by configure_task_storage; Podman reads it
# automatically via env var (more portable than --storage-conf CLI flag).
configure_task_storage

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