process ASSESS_KBET {
    tag 'assess-kbet'
    label 'process_kbet'

    container { params.goodworkflows_container }

    input:
    tuple val(meta), path(rds), path(prep_json), val(reduction), path(batch_metrics_utils), path(metric_script)

    output:
    tuple val(meta), val(reduction), path("${meta.id}_${reduction}_kbet.csv"), emit: metrics

    script:
    def outCsv = "${meta.id}_${reduction}_kbet.csv"
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
    uvr add --git https://github.com/theislab/kBET || \\
        Rscript -e "if (!requireNamespace('remotes', quietly=TRUE)) install.packages('remotes', repos='https://cloud.r-project.org'); remotes::install_github('theislab/kBET', upgrade='never')"
    uvr sync
    ln -sf "\${WORK_DIR}/${batch_metrics_utils}" "\${UVR_ROOT}/batch_metrics_utils.R"
    ln -sf "\${WORK_DIR}/${metric_script}" "\${UVR_ROOT}/${metric_script}"
    export RDS_PATH="\${WORK_DIR}/${rds}"
    export PREP_JSON="\${WORK_DIR}/${prep_json}"
    export REDUCTION='${reduction}'
    export KBET_CELLS_PER_BATCH='${params.batch_assessment_kbet_cells_per_batch}'
    export OUT_CSV="\${WORK_DIR}/${outCsv}"
    uvr run ${metric_script}
    """

    stub:
    """
    echo 'sample_id,reduction,metric,status' > ${meta.id}_${reduction}_kbet.csv
    echo '${meta.id},${reduction},kbet,stub' >> ${meta.id}_${reduction}_kbet.csv
    """
}
