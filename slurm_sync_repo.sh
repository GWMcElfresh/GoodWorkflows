#!/usr/bin/env bash
# slurm_sync_repo.sh – quick SLURM job for cloning or fast-forwarding the repo on HPC.
#
# Usage:
#   sbatch slurm_sync_repo.sh
#   sbatch --export=ALL,SYNC_TARGET_DIR=/gscratch/mygroup/GoodWorkflows slurm_sync_repo.sh
#   sbatch --export=ALL,REPO_BRANCH=main slurm_sync_repo.sh

#SBATCH --job-name=gw-sync
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=2000
#SBATCH --partition=batch
#SBATCH --time=00:10:00
#SBATCH --output=logs/slurm-sync-%j.out
#SBATCH --error=logs/slurm-sync-%j.err

set -euo pipefail

LOG_DIR="${PWD}/logs"
mkdir -p "$LOG_DIR"

SYNC_SCRIPT="${SYNC_SCRIPT:-${SLURM_SUBMIT_DIR}/scripts/sync_repo.sh}"
TARGET_DIR="${SYNC_TARGET_DIR:-$SLURM_SUBMIT_DIR}"

if ! command -v git >/dev/null 2>&1; then
    echo "ERROR: git is required for repository sync but is not available in PATH."
    exit 1
fi

bash "$SYNC_SCRIPT" "$TARGET_DIR"
