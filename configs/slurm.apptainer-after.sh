set -euo pipefail

# SIF files live in the shared NXF_SINGULARITY_CACHEDIR; they are persistent
# across jobs and are managed entirely by the pre-pull step.
# Nothing to clean up here on a per-task basis.
true
