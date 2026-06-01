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
    export PREP_JSON="${prep_json}"
    export ILISI_CSV="${ilisi_csv}"
    export CILISI_CSV="${cilisi_csv}"
    export ASW_CSV="${asw_csv}"
    export KBET_CSV="${kbet_csv}"
    export SUMMARY_CSV="${meta.id}_summary.csv"
    export PLOT_PNG="${meta.id}_metrics.png"
    export RUN_SUMMARY_CSV=''
    export R_LIBS="/usr/local/lib/R/site-library"
    Rscript "${collect_script}"
    touch "${meta.id}_metrics.png" 2>/dev/null || true
    """

    stub:
    """
    echo 'sample_id,metric,status' > ${meta.id}_summary.csv
    echo '${meta.id},ilisi,stub' >> ${meta.id}_summary.csv
    touch ${meta.id}_metrics.png
    """
}
