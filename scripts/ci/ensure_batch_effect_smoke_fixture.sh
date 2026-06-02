#!/usr/bin/env bash
# ensure_batch_effect_smoke_fixture.sh — Create SMOKE.rds for stub/smoke runs when missing.
#
# INGEST_FILE validates path existence before stub-run. CI and template/gw checks
# use test-data/batch_effect_assessments/samplesheet.csv with a relative path column.
# Prefer the R generator when Seurat is available; otherwise create an empty placeholder
# (stub-run path-existence only; real runs need a valid Seurat object — see create_batch_effect_smoke_rds.R).

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${PROJECT_DIR}/test-data/batch_effect_assessments/SMOKE.rds"

if [[ -f "${OUT}" ]]; then
    exit 0
fi

mkdir -p "$(dirname "${OUT}")"

if command -v Rscript &>/dev/null \
    && Rscript -e 'quit(status = if (requireNamespace("Seurat", quietly = TRUE)) 0 else 1)' 2>/dev/null; then
    if ! Rscript "${PROJECT_DIR}/scripts/ci/create_batch_effect_smoke_rds.R"; then
        echo "ERROR: failed to generate ${OUT} via create_batch_effect_smoke_rds.R" >&2
        echo "Real batch_effect_assessments runs require a valid Seurat RDS at that path." >&2
        exit 1
    fi
else
    echo "WARNING: Seurat not available; creating empty placeholder at ${OUT}" >&2
    echo "Stub-run only — run: Rscript scripts/ci/create_batch_effect_smoke_rds.R for real runs." >&2
    touch "${OUT}"
fi
