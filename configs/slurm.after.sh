set -euo pipefail

# Clean up the per-task ephemeral scratch created by slurm.before.sh.
JOB_STORAGE="${NXF_WORK:-.}/.podman-scratch/${SLURM_JOB_ID:-$$}"
rm -rf "${JOB_STORAGE}"