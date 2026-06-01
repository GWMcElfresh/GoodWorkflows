/*
 * PREP_BATCH_ASSESSMENT — discover reductions, infer celltype column, write prep JSON.
 * Runs in ghcr.io/gwmcelfresh/goodworkflows with system site-library R deps.
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
    export RDS_PATH="${rds}"
    export BATCH_COLUMN='${meta.batch_column}'
    export INTEGRATION_ASSESSMENT_METHODS='${methodsShell}'
    export MIN_CELLS_PER_BATCH='${params.batch_assessment_min_cells_per_batch}'
    export SAMPLE_ID='${meta.id}'
    export PREP_JSON="${meta.id}_prep.json"
    # System-installed packages (Seurat, jsonlite) are in /usr/local/lib/R/site-library.
    export R_LIBS="/usr/local/lib/R/site-library"
    Rscript "${prep_script}"
    """

    stub:
    """
    echo '{"sample_id":"${meta.id}","batch_column":"${meta.batch_column}","reductions":["pca"],"methods":["LISI"],"n_cells":100,"n_batches":2}' > ${meta.id}_prep.json
    """
}
