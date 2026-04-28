set -euo pipefail

resolve_podman_local_scratch() {
	local candidate

	for candidate in "${NXF_PODMAN_LOCAL_SCRATCH:-}" "${SLURM_TMPDIR:-}"; do
		[[ -n "${candidate}" ]] || continue
		if [[ -d "${candidate}" && -w "${candidate}" ]]; then
			printf '%s' "${candidate}"
			return 0
		fi
	done

	return 1
}

if local_scratch_root="$(resolve_podman_local_scratch 2>/dev/null)"; then
	JOB_STORAGE="${local_scratch_root%/}/goodworkflows-podman/${SLURM_JOB_ID:-$$}"
	rm -rf "${JOB_STORAGE}"
fi