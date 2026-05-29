process COLLECT_BATCH_ASSESSMENT {
    tag 'collect-batch-assessment'
    label 'process_tabulate'

    container { params.goodworkflows_container }

    publishDir "${params.outdir}/batch_effect_assessments", mode: 'copy', pattern: '*'

    input:
    tuple val(meta), path(prep_json), path(ilisi_csv), path(cilisi_csv), path(asw_csv), path(kbet_csv), path(collect_script)

    output:
    path("${meta.id}_summary.csv"), emit: summary
    path("${meta.id}_metrics.png"), emit: plot, optional: true

    script:
    """
    #!/usr/bin/env bash
    set -euo pipefail
    WORK_DIR="\${PWD}"
    UVR_ROOT="\${WORK_DIR}/.uvr-workspace"
    trap 'rm -rf "\${UVR_ROOT}"' EXIT
    mkdir -p "\${UVR_ROOT}"
    cd "\${UVR_ROOT}"
    uvr init --here
    uvr add jsonlite ggplot2
    uvr sync
    ln -sf "\${WORK_DIR}/${collect_script}" "\${UVR_ROOT}/${collect_script}"
    export PREP_JSON="\${WORK_DIR}/${prep_json}"
    export ILISI_CSV="\${WORK_DIR}/${ilisi_csv}"
    export CILISI_CSV="\${WORK_DIR}/${cilisi_csv}"
    export ASW_CSV="\${WORK_DIR}/${asw_csv}"
    export KBET_CSV="\${WORK_DIR}/${kbet_csv}"
    export SUMMARY_CSV="\${WORK_DIR}/${meta.id}_summary.csv"
    export PLOT_PNG="\${WORK_DIR}/${meta.id}_metrics.png"
    export RUN_SUMMARY_CSV=''
    uvr run ${collect_script}
    touch "\${WORK_DIR}/${meta.id}_metrics.png" 2>/dev/null || true
    """

    stub:
    """
    echo 'sample_id,metric,status' > ${meta.id}_summary.csv
    echo '${meta.id},ilisi,stub' >> ${meta.id}_summary.csv
    touch ${meta.id}_metrics.png
    """
}
