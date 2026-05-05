#!/usr/bin/env bash
set -euo pipefail

CACHE_DIR="${CACHE_DIR:-.ci/docker-cache}"
mkdir -p "${CACHE_DIR}"

# Sync this list with scripts/image-manifest.txt and template/gw/setup.sh
# whenever a new workflow/container is added.
IMAGES=(
  "ghcr.io/bimberlabinternal/rdiscvr:latest"
  "ghcr.io/bimberlabinternal/cellmembrane:latest"
  "ghcr.io/gwmcelfresh/scmodal:latest"
  "ghcr.io/gwmcelfresh/nmf-vae:latest"
)

for image in "${IMAGES[@]}"; do
    tar_name="$(echo "${image}" | tr '/:' '_').tar"
    tar_path="${CACHE_DIR}/${tar_name}"

    if [[ -f "${tar_path}" ]]; then
        echo "Loading cached image: ${image}"
        docker load -i "${tar_path}"
    else
        echo "Pulling image: ${image}"
        docker pull "${image}"
        docker save "${image}" -o "${tar_path}"
    fi

done

echo "Container cache primed in ${CACHE_DIR}"
