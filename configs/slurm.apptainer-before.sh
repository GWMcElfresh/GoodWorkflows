set -euo pipefail

if command -v module &>/dev/null; then
    module load apptainer 2>/dev/null \
        || module load singularity 2>/dev/null \
        || echo "Warning: neither 'module load apptainer' nor 'module load singularity' succeeded - continuing"
fi

echo "[APPTAINER_DIAG] SLURM_JOB_ID       : ${SLURM_JOB_ID:-local}"    >&2
echo "[APPTAINER_DIAG] SLURM_NODELIST     : ${SLURM_NODELIST:-local}"   >&2
echo "[APPTAINER_DIAG] APPTAINER_CACHEDIR : ${APPTAINER_CACHEDIR:-unset}" >&2
echo "[APPTAINER_DIAG] NXF_SINGULARITY_CACHEDIR : ${NXF_SINGULARITY_CACHEDIR:-unset}" >&2
