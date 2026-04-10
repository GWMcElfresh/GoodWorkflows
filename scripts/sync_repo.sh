#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${1:-${SYNC_TARGET_DIR:-$PWD}}"
REPO_URL="${REPO_URL:-https://github.com/GWMcElfresh/GoodWorkflows.git}"
REPO_BRANCH="${REPO_BRANCH:-main}"

mkdir -p "$(dirname "$TARGET_DIR")"

echo "=========================================="
echo " GoodWorkflows repository sync"
echo "=========================================="
echo " Target dir : $TARGET_DIR"
echo " Repo URL   : $REPO_URL"
echo " Branch     : $REPO_BRANCH"
echo "=========================================="

if [[ -d "$TARGET_DIR/.git" ]]; then
    echo "Existing checkout detected; fetching latest commits"
    git -C "$TARGET_DIR" fetch origin "$REPO_BRANCH" --prune
    git -C "$TARGET_DIR" checkout "$REPO_BRANCH"
    git -C "$TARGET_DIR" pull --ff-only origin "$REPO_BRANCH"
else
    if [[ -e "$TARGET_DIR" && -n "$(find "$TARGET_DIR" -mindepth 1 -maxdepth 1 2>/dev/null | head -n 1)" ]]; then
        echo "ERROR: target directory exists and is not an initialized git checkout: $TARGET_DIR"
        echo "       Use an empty directory or an existing clone."
        exit 1
    fi

    rm -rf "$TARGET_DIR"
    git clone --branch "$REPO_BRANCH" "$REPO_URL" "$TARGET_DIR"
fi

echo "Checked out commit:"
git -C "$TARGET_DIR" rev-parse HEAD
git -C "$TARGET_DIR" status --short --branch
