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

# The HPC sets SINGULARITYENV_* vars but we run under Apptainer.
# Unset the old-prefix vars so Apptainer doesn't inherit stale env.
# Re-export under the correct APPTAINERENV_ prefix so they take effect inside the container.
for _var in TMPDIR NXF_TASK_WORKDIR NXF_DEBUG; do
    if [ -n "${SINGULARITYENV_${_var}:-}" ]; then
        export "APPTAINERENV_${_var}=${SINGULARITYENV_${_var}}"
    fi
    unset "SINGULARITYENV_${_var}" 2>/dev/null || true
done

# Matplotlib cache dir — suppress the warning by pointing at a writable tmp location
export MPLCONFIGDIR="${APPTAINERENV_TMPDIR:-/tmp}/matplotlib_cache"

echo "[APPTAINER_DIAG] APPTAINERENV_TMPDIR       : ${APPTAINERENV_TMPDIR:-unset}" >&2
echo "[APPTAINER_DIAG] APPTAINERENV_NXF_TASK_WORKDIR: ${APPTAINERENV_NXF_TASK_WORKDIR:-unset}" >&2
echo "[APPTAINER_DIAG] MPLCONFIGDIR               : ${MPLCONFIGDIR}" >&2
