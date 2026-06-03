process COLLECT_BATCH_ASSESSMENT {
    tag 'collect-batch-assessment'
    label 'process_tabulate'

    container { params.goodworkflows_container }

    publishDir "${params.outdir}/batch_effect_assessments", mode: 'copy', pattern: '*'

    input:
    tuple val(meta), path(prep_json), val(reduction), path(ilisi_csv), path(cilisi_csv), path(asw_csv), path(kbet_csv), path(cilisi_cells_csv), path(asw_cells_csv), path(collect_script)

    output:
    path("${meta.id}_${reduction}_summary.csv"), emit: summary
    path("${meta.id}_${reduction}_metrics.png"), emit: plot, optional: true
    path("${meta.id}_${reduction}_celltype_assessment.png"), emit: celltype_plot, optional: true

    script:
    def cellsOut = "${meta.id}_${reduction}_celltype_assessment.png"
    """
    #!/usr/bin/env bash
    set -euo pipefail
    export PREP_JSON="${prep_json}"
    export ILISI_CSV="${ilisi_csv}"
    export CILISI_CSV="${cilisi_csv}"
    export ASW_CSV="${asw_csv}"
    export KBET_CSV="${kbet_csv}"
    export CILISI_CELLS_CSV="${cilisi_cells_csv}"
    export ASW_CELLS_CSV="${asw_cells_csv}"
    export SUMMARY_CSV="${meta.id}_${reduction}_summary.csv"
    export PLOT_PNG="${meta.id}_${reduction}_metrics.png"
    export CELLTYPE_PLOT_PNG="${cellsOut}"
    export RUN_SUMMARY_CSV=''
    export R_LIBS="/usr/local/lib/R/site-library"
    Rscript "${collect_script}"
    """

    stub:
    """
    echo 'sample_id,metric,status' > ${meta.id}_${reduction}_summary.csv
    echo '${meta.id},ilisi,stub' >> ${meta.id}_${reduction}_summary.csv
    touch ${meta.id}_${reduction}_metrics.png
    touch ${meta.id}_${reduction}_celltype_assessment.png
    """
}
