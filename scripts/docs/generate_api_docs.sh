#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${PROJECT_DIR}/.tmp"
XDG_CONFIG_HOME_LOCAL="${TMP_DIR}/nf-docs-xdg"
NFDOCS_CONFIG_DIR="${XDG_CONFIG_HOME_LOCAL}/nf-docs"
NFDOCS_OUTPUT_DIR="${PROJECT_DIR}/docs/api/generated"
NFDOCS_WORKSPACE_DIR="${TMP_DIR}/nf-docs-workspace"

if ! command -v rsync >/dev/null 2>&1; then
    echo "rsync is required to stage a filtered nf-docs workspace" >&2
    exit 1
fi

mkdir -p "${NFDOCS_CONFIG_DIR}"
cp "${PROJECT_DIR}/scripts/docs/nf-docs-config.yml" "${NFDOCS_CONFIG_DIR}/config.yaml"

if command -v python3 >/dev/null 2>&1; then
    cert_path="$(python3 - <<'PY'
try:
    import certifi
    print(certifi.where())
except Exception:
    print("")
PY
)"
    if [[ -n "${cert_path}" ]]; then
        export SSL_CERT_FILE="${cert_path}"
    fi
fi

rm -rf "${NFDOCS_OUTPUT_DIR}"
mkdir -p "${NFDOCS_OUTPUT_DIR}"

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME_LOCAL}"

rm -rf "${NFDOCS_WORKSPACE_DIR}"
mkdir -p "${NFDOCS_WORKSPACE_DIR}"

rsync -a --delete \
    --exclude '.tmp/' \
    --exclude 'tests/' \
    --exclude 'test-results/' \
    --exclude 'testing_space/' \
    --exclude 'work/' \
    --exclude 'outputs/' \
    --exclude 'logs/' \
    --exclude 'docs/api/generated/' \
    --exclude '.nextflow/' \
    --exclude '.nextflow*' \
    --exclude '.git/' \
    "${PROJECT_DIR}/" "${NFDOCS_WORKSPACE_DIR}/"

if [[ -e "${PROJECT_DIR}/.git" ]]; then
    ln -s "${PROJECT_DIR}/.git" "${NFDOCS_WORKSPACE_DIR}/.git"
fi

# nf-docs auto-downloads the language server via unauthenticated GitHub API calls.
# Pre-install the JAR (GITHUB_TOKEN on CI) so shared runners avoid rate limits.
bash "${PROJECT_DIR}/scripts/docs/ensure_language_server.sh"

uvx nf-docs generate "${NFDOCS_WORKSPACE_DIR}" \
    --format markdown \
    --output "${NFDOCS_OUTPUT_DIR}" \
    --title "GoodWorkflows API Reference" \
    --no-cache

uvx nf-docs generate "${NFDOCS_WORKSPACE_DIR}" \
    --format json \
    --title "GoodWorkflows API Reference" \
    --no-cache \
    > "${NFDOCS_OUTPUT_DIR}/pipeline-api.json"
