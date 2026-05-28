process ASSESS_ASW {
    tag 'assess-asw'
    label 'process_tabulate'

    container { params.goodworkflows_container }

    input:
    tuple val(meta), path(rds), path(prep_json), val(reduction)

    output:
    tuple val(meta), val(reduction), path("${meta.id}_${reduction}_asw.csv"), emit: metrics

    script:
    def tplDir = "${projectDir}/modules/local/batch_effect_assessments/templates"
    def outCsv = "${meta.id}_${reduction}_asw.csv"
    """
    #!/usr/bin/env bash
    set -euo pipefail
    WORK_DIR="\${PWD}"
    UVR_ROOT="\${WORK_DIR}/.uvr-workspace"
    trap 'rm -rf "\${UVR_ROOT}"' EXIT
    TPL='${tplDir}'
    cp "\${TPL}/batch_metrics_utils.R" "\${WORK_DIR}/"
    cp "\${TPL}/assess_asw.R" "\${WORK_DIR}/.command-metric.R"
    uvr init --directory "\${UVR_ROOT}"
    cd "\${UVR_ROOT}"
    uvr add Seurat jsonlite
    uvr add --git https://github.com/carmonalab/scIntegrationMetrics || \\
        Rscript -e "if (!requireNamespace('remotes', quietly=TRUE)) install.packages('remotes', repos='https://cloud.r-project.org'); remotes::install_github('carmonalab/scIntegrationMetrics', upgrade='never')"
    uvr sync
    export RDS_PATH='${rds}'
    export PREP_JSON='${prep_json}'
    export REDUCTION='${reduction}'
    export OUT_CSV="\${WORK_DIR}/${outCsv}"
    cd "\${WORK_DIR}"
    uvr run --directory "\${UVR_ROOT}" -- Rscript "\${WORK_DIR}/.command-metric.R"
    """

    stub:
    """
    echo 'sample_id,reduction,metric,status' > ${meta.id}_${reduction}_asw.csv
    echo '${meta.id},${reduction},asw,stub' >> ${meta.id}_${reduction}_asw.csv
    """
}
