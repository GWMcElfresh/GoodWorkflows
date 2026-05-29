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
    tuple val(meta), path(rds), path(batch_metrics_utils), path(prep_script)

    output:
    tuple val(meta), path("${meta.id}_prep.json"), emit: prep

    script:
    def methods = (meta.integration_assessment_methods ?: params.batch_assessment_default_methods).toString()
    def methodsShell = methods.replace("'", "'\"'\"'")
    """
    #!/usr/bin/env bash
    set -euo pipefail
    WORK_DIR="\${PWD}"
    UVR_ROOT="\${WORK_DIR}/.uvr-workspace"
    trap 'rm -rf "\${UVR_ROOT}"' EXIT
    mkdir -p "\${UVR_ROOT}"
    cd "\${UVR_ROOT}"
    uvr init --here
    uvr add Seurat jsonlite
    uvr sync
    ln -sf "\${WORK_DIR}/${batch_metrics_utils}" "\${UVR_ROOT}/batch_metrics_utils.R"
    ln -sf "\${WORK_DIR}/${prep_script}" "\${UVR_ROOT}/${prep_script}"
    export RDS_PATH="\${WORK_DIR}/${rds}"
    export BATCH_COLUMN='${meta.batch_column}'
    export INTEGRATION_ASSESSMENT_METHODS='${methodsShell}'
    export MIN_CELLS_PER_BATCH='${params.batch_assessment_min_cells_per_batch}'
    export SAMPLE_ID='${meta.id}'
    export PREP_JSON="\${WORK_DIR}/${meta.id}_prep.json"
    uvr run ${prep_script}
    """

    stub:
    """
    echo '{"sample_id":"${meta.id}","batch_column":"${meta.batch_column}","reductions":["pca"],"methods":["LISI"],"n_cells":100,"n_batches":2}' > ${meta.id}_prep.json
    """
}
