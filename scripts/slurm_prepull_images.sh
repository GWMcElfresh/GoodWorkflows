#!/usr/bin/env bash
# Discover and pre-pull container images needed by the selected workflow.
#
# This script is idempotent: existing images are skipped. It can be submitted
# via sbatch or run directly inside another SLURM allocation.
#
# Rootless Podman graphRoot must live on node-local storage, not gscratch/NFS.
# This script uses SLURM local disk (SLURM_TMPDIR) or an explicit
# NXF_PODMAN_LOCAL_SCRATCH override for Podman graphroot, then exports each
# pulled image as a plain OCI archive into a shared cache on NXF_WORK so tasks
# on other nodes can load it without hitting the registry.

#SBATCH --job-name=nf-prepull
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8000
#SBATCH --partition=batch
#SBATCH --time=04:00:00
#SBATCH --gres=disk:1028
#SBATCH --output=logs/slurm-prepull-%j.out
#SBATCH --error=logs/slurm-prepull-%j.err

set -euo pipefail

PIPELINE_ROOT="${PIPELINE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
NEXTFLOW_BIN="${NEXTFLOW_BIN:-/gscratch/CHANGEME/nextflow}"
export NXF_HOME="${NXF_HOME:-/gscratch/CHANGEME/.nextflow}"
NXF_WORK_ROOT="${NXF_WORK:-${PWD}/work}"
MANIFEST_PATH="${PIPELINE_ROOT}/scripts/image-manifest.txt"

# shellcheck source=configs/slurm.podman-local.sh
source "${PIPELINE_ROOT}/configs/slurm.podman-local.sh"

podman_cache_key() {
    printf '%s' "$1" | tr '/:@' '___' | tr -cd '[:alnum:]_.-'
}

podman_archive_ready() {
    local image="$1"
    local key archive

    key="$(podman_cache_key "${image}")"
    archive="${NXF_PODMAN_CACHEDIR}/${key}.tar"
    [[ -f "${archive}.done" ]]
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

configure_podman_storage() {
    local local_scratch_root local_scratch_fs_type fuse_overlayfs_bin

    local_scratch_root="$(nxf_resolve_podman_local_scratch)"
    local_scratch_fs_type="$(nxf_podman_fs_type "${local_scratch_root}")"
    JOB_STORAGE="${local_scratch_root%/}/goodworkflows-podman/${SLURM_JOB_ID:-$$}"
    export CONTAINERS_RUNROOT="${JOB_STORAGE}/run"
    export TMPDIR="${JOB_STORAGE}/tmp"
    export XDG_RUNTIME_DIR="${JOB_STORAGE}/xdg-${UID}"
    export NXF_PODMAN_CACHEDIR="${NXF_PODMAN_CACHEDIR:-${NXF_WORK_ROOT}/.podman-oci-cache}"
    export CONTAINERS_STORAGE_CONF="${JOB_STORAGE}/storage.conf"
    export NXF_PODMAN_PULL_LOCK_DIR="${NXF_PODMAN_PULL_LOCK_DIR:-${NXF_WORK_ROOT}/.podman-pull-locks}"

    mkdir -p "${JOB_STORAGE}/storage" "${CONTAINERS_RUNROOT}" "${TMPDIR}" "${XDG_RUNTIME_DIR}" \
             "${NXF_PODMAN_CACHEDIR}" "${NXF_PODMAN_PULL_LOCK_DIR}" "${PWD}/logs"
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

    echo "[PODMAN_DIAG] local_scratch_root=${local_scratch_root}"
    echo "[PODMAN_DIAG] local_scratch_fs_type=${local_scratch_fs_type}"
    echo "[PODMAN_DIAG] job_storage=${JOB_STORAGE}"
    echo "[PODMAN_DIAG] containers_storage_conf=${CONTAINERS_STORAGE_CONF}"
    echo "[PODMAN_DIAG] containers_runroot=${CONTAINERS_RUNROOT}"
    echo "[PODMAN_DIAG] tmpdir=${TMPDIR}"
    echo "[PODMAN_DIAG] oci_cache=${NXF_PODMAN_CACHEDIR}"
    echo "[PODMAN_DIAG] pull_lock_dir=${NXF_PODMAN_PULL_LOCK_DIR}"
}

if command -v module &>/dev/null; then
    module load podman 2>/dev/null || true
fi

configure_podman_storage
trap 'rm -rf "${JOB_STORAGE}"' EXIT

if ! command -v podman >/dev/null 2>&1; then
    echo "ERROR: podman is not available in PATH for pre-pull job."
    exit 1
fi

echo "=========================================="
echo " GoodWorkflows Container Pre-Pull"
echo "=========================================="
echo " SLURM_JOB_ID   : ${SLURM_JOB_ID:-local}"
echo " Working dir    : ${PWD}"
echo " Pipeline root  : ${PIPELINE_ROOT}"
echo " Job storage    : ${JOB_STORAGE}"
echo " Podman graphRoot: ${JOB_STORAGE}/storage"
echo " OCI cache dir  : ${NXF_PODMAN_CACHEDIR}"
echo " Pull lock dir  : ${NXF_PODMAN_PULL_LOCK_DIR}"
df -h "${JOB_STORAGE}" || true
df -i "${JOB_STORAGE}" || true
echo "=========================================="

cleanup_stale_locks() {
    find "${NXF_PODMAN_PULL_LOCK_DIR}" -maxdepth 1 -type f -name '*.lock' -mmin +120 -delete 2>/dev/null || true
    find "${NXF_PODMAN_PULL_LOCK_DIR}" -maxdepth 1 -type d -name '*.lock.d' -mmin +120 -exec rm -rf {} + 2>/dev/null || true
}

load_manifest_images() {
    if [[ ! -f "${MANIFEST_PATH}" ]]; then
        return 1
    fi

    mapfile -t DISCOVERED_IMAGES < <(grep -Ev '^[[:space:]]*(#|$)' "${MANIFEST_PATH}" | sort -u)
    [[ ${#DISCOVERED_IMAGES[@]} -gt 0 ]]
}

podman_pull_once() {
    local image="$1"

    if command -v timeout &>/dev/null; then
        timeout 3600 podman pull "${image}"
    else
        podman pull "${image}"
    fi
}

declare -a DISCOVERED_IMAGES
mapfile -t DISCOVERED_IMAGES < <(
python3 - "${PIPELINE_ROOT}" "$@" <<'PY'
import json
import re
import sys
from pathlib import Path

pipeline_root = Path(sys.argv[1]).resolve()
cli_args = sys.argv[2:]

params = {}

def parse_params_block(text):
    out = {}
    for block in re.finditer(r"params\s*\{(.*?)\}", text, re.DOTALL):
        body = block.group(1)
        for raw in body.splitlines():
            line = raw.split('//', 1)[0].strip()
            if not line or '=' not in line:
                continue
            key, val = line.split('=', 1)
            key = key.strip()
            val = val.strip().rstrip(',')
            if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
                continue
            if val.startswith(('"', "'")) and val.endswith(('"', "'")) and len(val) >= 2:
                out[key] = val[1:-1]
            else:
                out[key] = val
    return out

for cfg in [pipeline_root / 'nextflow.config', pipeline_root / 'configs' / 'base.config']:
    if cfg.exists():
        params.update(parse_params_block(cfg.read_text()))

params_file = os.environ.get('NXF_PARAMS_FILE', '').strip()
if params_file:
    p = Path(params_file)
    if p.exists() and p.suffix.lower() == '.json':
        try:
            data = json.loads(p.read_text())
            if isinstance(data, dict):
                for k, v in data.items():
                    params[str(k)] = '' if v is None else str(v)
        except Exception:
            pass

i = 0
while i < len(cli_args):
    tok = cli_args[i]
    if tok.startswith('--') and len(tok) > 2:
        if '=' in tok:
            key, value = tok[2:].split('=', 1)
            params[key] = value
        else:
            key = tok[2:]
            if i + 1 < len(cli_args) and not cli_args[i + 1].startswith('-'):
                params[key] = cli_args[i + 1]
                i += 1
            else:
                params[key] = 'true'
    i += 1

selected_workflow = params.get('workflow', 'integration').strip() or 'integration'

main_nf = pipeline_root / 'main.nf'
include_map = {}
case_to_alias = {}
if main_nf.exists():
    text = main_nf.read_text()
    for m in re.finditer(r"include\s*\{\s*([A-Za-z0-9_]+)\s*\}\s*from\s*['\"]([^'\"]+)['\"]", text):
        include_map[m.group(1)] = m.group(2)
    for m in re.finditer(r"case\s*'([^']+)'\s*:\s*([A-Za-z0-9_]+)\s*\(", text, re.DOTALL):
        case_to_alias[m.group(1)] = m.group(2)

root_files = []
alias = case_to_alias.get(selected_workflow)
if alias and alias in include_map:
    root_files = [include_map[alias]]
else:
    root_files = list(include_map.values())

def resolve(base_file, rel):
    return (base_file.parent / rel).resolve()

queue = []
visited = set()
if root_files:
    for rel in root_files:
        queue.append((pipeline_root / rel).resolve())
else:
    queue.append(main_nf)

all_files = []
while queue:
    fp = queue.pop(0)
    if not fp.exists():
        continue
    key = str(fp)
    if key in visited:
        continue
    visited.add(key)
    all_files.append(fp)
    txt = fp.read_text()
    for m in re.finditer(r"include\s*\{\s*[A-Za-z0-9_]+\s*\}\s*from\s*['\"]([^'\"]+)['\"]", txt):
        queue.append(resolve(fp, m.group(1)))

images = set()
for fp in all_files:
    txt = fp.read_text()
    for m in re.finditer(r"^\s*container\s+(.+?)\s*$", txt, re.MULTILINE):
        expr = m.group(1).split('//', 1)[0].strip()
        if not expr:
            continue
        if expr.startswith(('"', "'")) and expr.endswith(('"', "'")) and len(expr) >= 2:
            expr = expr[1:-1]
        expr = re.sub(r"\$\{params\.([A-Za-z0-9_]+)\}", lambda mm: str(params.get(mm.group(1), mm.group(0))), expr)
        expr = expr.strip()
        if not expr:
            continue
        if '${' in expr:
            continue
        if ':' not in expr or '/' not in expr:
            continue
        images.add(expr)

for image in sorted(images):
    print(image)
PY
)

if [[ ${#DISCOVERED_IMAGES[@]} -eq 0 ]]; then
    echo "Dynamic discovery returned no images; falling back to manifest: ${MANIFEST_PATH}"
    load_manifest_images || true
fi

if [[ ${#DISCOVERED_IMAGES[@]} -eq 0 ]]; then
    echo "WARNING: No container images discovered; skipping pre-pull."
    exit 0
fi

echo "Discovered images (${#DISCOVERED_IMAGES[@]}):"
for img in "${DISCOVERED_IMAGES[@]}"; do
    echo "  - ${img}"
done

pull_with_lock() {
    local image="$1"
    local key lock_file lock_dir attempt wait_s lock_fd status

    key="$(printf '%s' "${image}" | tr '/:@' '___' | tr -cd '[:alnum:]_.-')"
    lock_file="${NXF_PODMAN_PULL_LOCK_DIR}/${key}.lock"
    lock_dir="${lock_file}.d"
    status=1

    if command -v flock &>/dev/null; then
        exec {lock_fd}>"${lock_file}"
        flock "${lock_fd}"
        if podman_archive_ready "${image}"; then
            echo "[SKIP] OCI archive already exists: ${image}"
            status=0
        elif podman image exists "${image}" 2>/dev/null; then
            echo "[SKIP] Image already present: ${image}"
            export_oci_archive "${image}" || true
            status=0
        else
            for attempt in 1 2 3; do
                if podman_pull_once "${image}"; then
                    echo "[OK] Pulled ${image}"
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

    if podman_archive_ready "${image}"; then
        echo "[SKIP] OCI archive already exists: ${image}"
        status=0
    elif podman image exists "${image}" 2>/dev/null; then
        echo "[SKIP] Image already present: ${image}"
        export_oci_archive "${image}" || true
        status=0
    else
        for attempt in 1 2 3; do
            if podman_pull_once "${image}"; then
                echo "[OK] Pulled ${image}"
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

pull_all_images() {
    local image

    cleanup_stale_locks
    for image in "${DISCOVERED_IMAGES[@]}"; do
        pull_with_lock "${image}"
    done
}

run_with_global_lock() {
    local global_lock_file global_lock_dir lock_fd status

    global_lock_file="${NXF_PODMAN_PULL_LOCK_DIR}/prepull-global.lock"
    global_lock_dir="${global_lock_file}.d"

    if command -v flock &>/dev/null; then
        exec {lock_fd}>"${global_lock_file}"
        flock "${lock_fd}"
        "$@"
        status=$?
        flock -u "${lock_fd}"
        exec {lock_fd}>&-
        rm -f "${global_lock_file}"
        return "${status}"
    fi

    until mkdir "${global_lock_dir}" 2>/dev/null; do
        sleep $((2 + RANDOM % 4))
    done
    "$@"
    status=$?
    rmdir "${global_lock_dir}" 2>/dev/null || true
    return "${status}"
}

run_with_global_lock pull_all_images

echo "Pre-pull complete."
