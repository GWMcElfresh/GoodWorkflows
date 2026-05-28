/*
 * PREP_BATCH_ASSESSMENT — discover reductions, infer celltype column, write prep JSON.
 * Runs in ghcr.io/gwmcelfresh/goodworkflows with transient uvr project (cleaned on exit).
 */

process PREP_BATCH_ASSESSMENT {
    tag 'prep-batch-assessment'
    label 'process_tabulate'

    container { params.goodworkflows_container }

    publishDir "${params.outdir}/batch_effect_assessments", mode: 'copy', pattern: '*_prep.json'

    input:
    tuple val(meta), path(rds)

    output:
    tuple val(meta), path("${meta.id}_prep.json"), emit: prep

    script:
    def tplDir = "${projectDir}/modules/local/batch_effect_assessments/templates"
    def methods = meta.integration_assessment_methods ?: params.batch_assessment_default_methods
    """
    #!/usr/bin/env bash
    set -euo pipefail
    WORK_DIR="\${PWD}"
    UVR_ROOT="\${WORK_DIR}/.uvr-workspace"
    trap 'rm -rf "\${UVR_ROOT}"' EXIT
    TPL='${tplDir}'
    cp "\${TPL}/batch_metrics_utils.R" "\${WORK_DIR}/"
    cp "\${TPL}/prep_batch_assessment.R" "\${WORK_DIR}/.command-prep.R"
    uvr init --directory "\${UVR_ROOT}"
    cd "\${UVR_ROOT}"
    uvr add Seurat jsonlite
    uvr sync
    export RDS_PATH='${rds}'
    export BATCH_COLUMN='${meta.batch_column}'
    export INTEGRATION_ASSESSMENT_METHODS='${methods}'
    export MIN_CELLS_PER_BATCH='${params.batch_assessment_min_cells_per_batch}'
    export SAMPLE_ID='${meta.id}'
    export PREP_JSON="\${WORK_DIR}/${meta.id}_prep.json"
    cd "\${WORK_DIR}"
    uvr run --directory "\${UVR_ROOT}" -- Rscript "\${WORK_DIR}/.command-prep.R"
    """

    stub:
    """
    echo '{"sample_id":"${meta.id}","batch_column":"${meta.batch_column}","reductions":["pca"],"methods":["LISI"],"n_cells":100,"n_batches":2}' > ${meta.id}_prep.json
    """
}
