process COLLECT_BATCH_ASSESSMENT {
    tag 'collect-batch-assessment'
    label 'process_tabulate'

    container { params.goodworkflows_container }

    publishDir "${params.outdir}/batch_effect_assessments", mode: 'copy', pattern: '*'

    input:
    tuple val(meta), path(prep_json), path(ilisi_csv), path(cilisi_csv), path(asw_csv), path(kbet_csv)

    output:
    path("${meta.id}_summary.csv"), emit: summary
    path("${meta.id}_metrics.png"), emit: plot, optional: true

    script:
    def tplDir = "${projectDir}/modules/local/batch_effect_assessments/templates"
    """
    #!/usr/bin/env bash
    set -euo pipefail
    WORK_DIR="\${PWD}"
    UVR_ROOT="\${WORK_DIR}/.uvr-workspace"
    trap 'rm -rf "\${UVR_ROOT}"' EXIT
    TPL='${tplDir}'
    cp "\${TPL}/collect_batch_assessment.R" "\${WORK_DIR}/.command-collect.R"
    uvr init --directory "\${UVR_ROOT}"
    cd "\${UVR_ROOT}"
    uvr add jsonlite ggplot2
    uvr sync
    export PREP_JSON='${prep_json}'
    export ILISI_CSV='${ilisi_csv}'
    export CILISI_CSV='${cilisi_csv}'
    export ASW_CSV='${asw_csv}'
    export KBET_CSV='${kbet_csv}'
    export SUMMARY_CSV="\${WORK_DIR}/${meta.id}_summary.csv"
    export PLOT_PNG="\${WORK_DIR}/${meta.id}_metrics.png"
    export RUN_SUMMARY_CSV=''
    cd "\${WORK_DIR}"
    uvr run --directory "\${UVR_ROOT}" -- Rscript "\${WORK_DIR}/.command-collect.R"
    touch "\${WORK_DIR}/${meta.id}_metrics.png" 2>/dev/null || true
    """

    stub:
    """
    echo 'sample_id,metric,status' > ${meta.id}_summary.csv
    echo '${meta.id},ilisi,stub' >> ${meta.id}_summary.csv
    touch ${meta.id}_metrics.png
    """
}
