#!/usr/bin/env bash
# Ensure nf-docs can find the Nextflow language server JAR without unauthenticated
# GitHub API calls (which hit rate limits on shared CI runners).
#
# nf-docs searches: ${XDG_DATA_HOME:-~/.local/share}/nf-docs/language-server-all.jar
#
# Usage:
#   ensure_language_server.sh                 # download if missing
#   ensure_language_server.sh --print-release-tag
set -euo pipefail

LANGUAGE_SERVER_REPO="nextflow-io/language-server"
LANGUAGE_SERVER_JAR="language-server-all.jar"
XDG_DATA="${XDG_DATA_HOME:-${HOME}/.local/share}"
LSP_DIR="${XDG_DATA}/nf-docs"
LSP_JAR="${LSP_DIR}/${LANGUAGE_SERVER_JAR}"
RELEASES_API="https://api.github.com/repos/${LANGUAGE_SERVER_REPO}/releases/latest"

github_api() {
    local url="$1"
    local -a auth_header=()

    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        auth_header=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    elif [[ -n "${GH_TOKEN:-}" ]]; then
        auth_header=(-H "Authorization: Bearer ${GH_TOKEN}")
    fi

    curl -fsSL "${auth_header[@]}" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "${url}"
}

fetch_release_json() {
    github_api "${RELEASES_API}"
}

parse_release() {
    local mode="$1"
    fetch_release_json | python3 -c "
import json
import sys

data = json.load(sys.stdin)
mode = sys.argv[1]
if mode == 'tag':
    print(data['tag_name'])
elif mode == 'jar_url':
    for asset in data.get('assets', []):
        if asset.get('name') == '${LANGUAGE_SERVER_JAR}':
            print(asset['browser_download_url'])
            break
    else:
        raise SystemExit('Could not find ${LANGUAGE_SERVER_JAR} in latest release')
else:
    raise SystemExit(f'unknown mode: {mode}')
" "${mode}"
}

case "${1:-}" in
    --print-release-tag)
        parse_release tag
        exit 0
        ;;
    --help|-h)
        echo "Usage: $0 [--print-release-tag]" >&2
        exit 0
        ;;
    "")
        ;;
    *)
        echo "Unknown option: $1" >&2
        echo "Usage: $0 [--print-release-tag]" >&2
        exit 1
        ;;
esac

if [[ -s "${LSP_JAR}" ]]; then
    echo "Nextflow language server already present: ${LSP_JAR}"
    exit 0
fi

mkdir -p "${LSP_DIR}"
jar_url="$(parse_release jar_url)"
echo "Downloading Nextflow language server to ${LSP_JAR}"
curl -fsSL -o "${LSP_JAR}" "${jar_url}"
echo "Downloaded Nextflow language server (${LANGUAGE_SERVER_JAR})"
