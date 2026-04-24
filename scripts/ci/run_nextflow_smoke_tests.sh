#!/usr/bin/env bash
set -euo pipefail

TEST_KIND="${1:-}"
TEST_NAME="${2:-}"
EXTRA_PIPELINE_ARGS=("${@:3}")

if [[ -z "${TEST_KIND}" || -z "${TEST_NAME}" ]]; then
    echo "Usage: $0 <workflow|module> <name>"
    exit 1
fi

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="${PROJECT_DIR}/test-results/${TEST_KIND}/${TEST_NAME}"
LABKEY_BASE_URL="${CI_LABKEY_BASE_URL:-https://labkey.example.org}"
LABKEY_FOLDER="${CI_LABKEY_FOLDER:-/Example/Folder}"

rm -rf "${TEST_ROOT}"
mkdir -p "${TEST_ROOT}"

run_nextflow() {
    nextflow \
        -log "${TEST_ROOT}/nextflow.log" \
        run "$1" \
        -profile test \
        -stub-run \
        -ansi-log false \
        -work-dir "${TEST_ROOT}/work" \
        -with-report "${TEST_ROOT}/report.html" \
        -with-trace "${TEST_ROOT}/trace.txt" \
        --input "${PROJECT_DIR}/data/samplesheet.csv" \
        --outdir "${TEST_ROOT}/outputs" \
        --labkey_base_url "${LABKEY_BASE_URL}" \
        --labkey_folder "${LABKEY_FOLDER}" \
        "${@:2}"
}

case "${TEST_KIND}" in
    workflow)
        run_nextflow "${PROJECT_DIR}/main.nf" --workflow "${TEST_NAME}" "${EXTRA_PIPELINE_ARGS[@]}"
        case "${TEST_NAME}" in
            ingest_export)
                test -f "${TEST_ROOT}/outputs/ingest/SAMPLE_01/SAMPLE_01.rds"
                test -f "${TEST_ROOT}/outputs/counts/SAMPLE_01/SAMPLE_01_counts/matrix.mtx"
                ;;
            ingest_tabulate)
                test -f "${TEST_ROOT}/outputs/ingest/SAMPLE_01/SAMPLE_01_metadata.csv"
                test -f "${TEST_ROOT}/outputs/tabulate/subjectIdTable.csv"
                ;;
            integration)
                test -f "${TEST_ROOT}/outputs/harmonized/harmonized_outputs/integration_manifest.csv"
                test -f "${TEST_ROOT}/outputs/scmodal/model_outputs/latent_clustered.h5ad"
                ;;
            *)
                echo "Unknown workflow smoke test: ${TEST_NAME}"
                exit 1
                ;;
        esac
        ;;
    module)
        run_nextflow "${PROJECT_DIR}/tests/modules/${TEST_NAME}.nf"
        case "${TEST_NAME}" in
            ingest)
                test -f "${TEST_ROOT}/outputs/ingest/TEST_SAMPLE/TEST_SAMPLE.rds"
                ;;
            ingest_metadata)
                test -f "${TEST_ROOT}/outputs/ingest/TEST_SAMPLE/TEST_SAMPLE_metadata.csv"
                ;;
            export_counts)
                test -f "${TEST_ROOT}/outputs/counts/TEST_SAMPLE/TEST_SAMPLE_counts/matrix.mtx"
                ;;
            gene_harmonize)
                test -f "${TEST_ROOT}/outputs/harmonized/harmonized_outputs/integration_manifest.csv"
                ;;
            scmodal_integrate)
                test -f "${TEST_ROOT}/outputs/scmodal/model_outputs/latent_clustered.h5ad"
                ;;
            tabulate)
                test -f "${TEST_ROOT}/outputs/tabulate/subjectIdTable.csv"
                ;;
            *)
                echo "Unknown module smoke test: ${TEST_NAME}"
                exit 1
                ;;
        esac
        ;;
    *)
        echo "Unsupported test kind: ${TEST_KIND}"
        exit 1
        ;;
esac

echo "Smoke test completed: ${TEST_KIND}/${TEST_NAME}"
