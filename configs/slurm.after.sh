set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=configs/slurm.podman-local.sh
source "${SCRIPT_DIR}/slurm.podman-local.sh"

if JOB_STORAGE="$(nxf_current_podman_job_storage 2>/dev/null)"; then
	rm -rf "${JOB_STORAGE}"
fi