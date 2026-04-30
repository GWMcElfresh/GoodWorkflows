#!/usr/bin/env bash
set -euo pipefail

CACHE_DIR="${CACHE_DIR:-.ci/docker-cache}"
mkdir -p "${CACHE_DIR}"

IMAGES=(
  "ghcr.io/bimberlabinternal/rdiscvr:latest"
  "ghcr.io/bimberlabinternal/cellmembrane:latest"
  "ghcr.io/gwmcelfresh/scmodal:sha-37c41f9"
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
