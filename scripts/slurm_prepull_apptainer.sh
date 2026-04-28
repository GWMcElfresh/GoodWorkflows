#!/usr/bin/env bash
# Discover and pre-pull container images needed by the selected workflow,
# converting each docker image to an Apptainer SIF file.
#
# This script is idempotent: existing SIF files are skipped. It can be submitted
# via sbatch or run directly inside another SLURM allocation.
#
# Image storage strategy:
#   - SIF files are written to NXF_SINGULARITY_CACHEDIR (default:
#     ${PIPELINE_ROOT}/apptainer-sif). This is the shared persistent cache that
#     Nextflow's singularity.cacheDir points to.
#   - APPTAINER_CACHEDIR (set in ~/.bashrc) is the OCI blob/layer cache used
#     internally by apptainer during conversion. It is passed through unchanged.
#   - Only lock files and temporary partial SIFs (*.img.tmp) go to scratch and
#     are cleaned up on exit.

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

# SIF output directory – where Nextflow (singularity.cacheDir) expects to find images.
NXF_SINGULARITY_CACHEDIR="${NXF_SINGULARITY_CACHEDIR:-${PIPELINE_ROOT}/apptainer-sif}"
export NXF_SINGULARITY_CACHEDIR
mkdir -p "${NXF_SINGULARITY_CACHEDIR}"

# Lock directory for coordinating concurrent pulls.
NXF_APPTAINER_PULL_LOCK_DIR="${NXF_APPTAINER_PULL_LOCK_DIR:-${NXF_WORK_ROOT}/.apptainer-pull-locks}"
export NXF_APPTAINER_PULL_LOCK_DIR
mkdir -p "${NXF_APPTAINER_PULL_LOCK_DIR}"

# Clean up any partial *.img.tmp files left by interrupted pulls.
trap 'find "${NXF_SINGULARITY_CACHEDIR}" -maxdepth 1 -name "*.img.tmp" -delete 2>/dev/null || true' EXIT

if command -v module &>/dev/null; then
    module load apptainer 2>/dev/null \
        || module load singularity 2>/dev/null \
        || echo "Warning: neither 'module load apptainer' nor 'module load singularity' succeeded"
fi

if ! command -v apptainer >/dev/null 2>&1 && ! command -v singularity >/dev/null 2>&1; then
    echo "ERROR: neither apptainer nor singularity is available in PATH for pre-pull job."
    exit 1
fi

# Prefer apptainer; fall back to singularity binary name.
APPTAINER_BIN="apptainer"
if ! command -v apptainer >/dev/null 2>&1; then
    APPTAINER_BIN="singularity"
fi

# Convert a docker image URI to the SIF filename Nextflow uses.
# Nextflow (nf-core convention): replace '/' and ':' with '-', append '.img'
# e.g. ghcr.io/bimberlabinternal/rdiscvr:latest -> ghcr.io-bimberlabinternal-rdiscvr-latest.img
image_to_sif_name() {
    local image="$1"
    printf '%s' "${image}" | tr '/: ' '---' | sed 's/@/-/g'
    printf '.img'
}

echo "=========================================="
echo " GoodWorkflows Apptainer Container Pre-Pull"
echo "=========================================="
echo " SLURM_JOB_ID   : ${SLURM_JOB_ID:-local}"
echo " Working dir    : ${PWD}"
echo " Pipeline root  : ${PIPELINE_ROOT}"
echo " SIF cache      : ${NXF_SINGULARITY_CACHEDIR}"
echo " APPTAINER_CACHEDIR : ${APPTAINER_CACHEDIR:-unset}"
echo " Pull lock dir  : ${NXF_APPTAINER_PULL_LOCK_DIR}"
df -h "${NXF_SINGULARITY_CACHEDIR}" || true
echo "=========================================="

cleanup_stale_locks() {
    find "${NXF_APPTAINER_PULL_LOCK_DIR}" -maxdepth 1 -type f -name '*.lock' -mmin +120 -delete 2>/dev/null || true
    find "${NXF_APPTAINER_PULL_LOCK_DIR}" -maxdepth 1 -type d -name '*.lock.d' -mmin +120 -exec rm -rf {} + 2>/dev/null || true
}

load_manifest_images() {
    if [[ ! -f "${MANIFEST_PATH}" ]]; then
        return 1
    fi

    mapfile -t DISCOVERED_IMAGES < <(grep -Ev '^[[:space:]]*(#|$)' "${MANIFEST_PATH}" | sort -u)
    [[ ${#DISCOVERED_IMAGES[@]} -gt 0 ]]
}

apptainer_pull_once() {
    local image="$1"
    local sif_name sif_path tmp_path

    sif_name="$(image_to_sif_name "${image}")"
    sif_path="${NXF_SINGULARITY_CACHEDIR}/${sif_name}"
    tmp_path="${sif_path}.tmp"

    if command -v timeout &>/dev/null; then
        timeout 3600 command "${APPTAINER_BIN}" pull --name "${tmp_path}" "docker://${image}"
    else
        command "${APPTAINER_BIN}" pull --name "${tmp_path}" "docker://${image}"
    fi

    # Atomic rename: only make the SIF visible to Nextflow once fully written.
    mv "${tmp_path}" "${sif_path}"
}

declare -a DISCOVERED_IMAGES
mapfile -t DISCOVERED_IMAGES < <(
python3 - "${PIPELINE_ROOT}" "$@" <<'PY'
import json
import os
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
    sif="$(image_to_sif_name "${img}")"
    echo "  - ${img}  ->  ${sif}"
done

pull_with_lock() {
    local image="$1"
    local sif_name sif_path key lock_file lock_dir attempt wait_s lock_fd status

    sif_name="$(image_to_sif_name "${image}")"
    sif_path="${NXF_SINGULARITY_CACHEDIR}/${sif_name}"

    key="$(printf '%s' "${image}" | tr '/:@' '___' | tr -cd '[:alnum:]_.-')"
    lock_file="${NXF_APPTAINER_PULL_LOCK_DIR}/${key}.lock"
    lock_dir="${lock_file}.d"
    status=1

    if command -v flock &>/dev/null; then
        exec {lock_fd}>"${lock_file}"
        flock "${lock_fd}"
        if [[ -f "${sif_path}" ]]; then
            echo "[SKIP] SIF already present: ${sif_path}"
            status=0
        else
            for attempt in 1 2 3; do
                if apptainer_pull_once "${image}"; then
                    echo "[OK] Pulled ${image} -> ${sif_path}"
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

    # flock not available: use a mkdir-based lock
    until mkdir "${lock_dir}" 2>/dev/null; do
        sleep $((2 + RANDOM % 4))
    done

    if [[ -f "${sif_path}" ]]; then
        echo "[SKIP] SIF already present: ${sif_path}"
        status=0
    else
        for attempt in 1 2 3; do
            if apptainer_pull_once "${image}"; then
                echo "[OK] Pulled ${image} -> ${sif_path}"
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

    global_lock_file="${NXF_APPTAINER_PULL_LOCK_DIR}/prepull-global.lock"
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
