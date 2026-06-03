process ASSESS_ASW {
    tag 'assess-asw'
    label 'process_tabulate'

    container { params.goodworkflows_container }

    input:
    tuple val(meta), path(rds), path(prep_json), val(reduction), path(batch_metrics_utils), path(metric_script)

    output:
    tuple val(meta), val(reduction), path("${meta.id}_${reduction}_asw.csv"), emit: metrics
    tuple val(meta), val(reduction), path("${meta.id}_${reduction}_asw_cells.csv"), emit: cells

    script:
    def outCsv = "${meta.id}_${reduction}_asw.csv"
    def cellsCsv = "${meta.id}_${reduction}_asw_cells.csv"
    """
    #!/usr/bin/env bash
    set -euo pipefail
    export RDS_PATH="${rds}"
    export PREP_JSON="${prep_json}"
    export REDUCTION='${reduction}'
    export OUT_CSV="${outCsv}"
    export ASW_CELLS_CSV="${cellsCsv}"
    export R_LIBS="/usr/local/lib/R/site-library"
    if ! Rscript -e "suppressPackageStartupMessages(library(scIntegrationMetrics))" 2>/dev/null; then
        R_LIB_TMP="\${PWD}/.r-lib"
        mkdir -p "\${R_LIB_TMP}"
        Rscript -e "install.packages('remotes', repos='https://cloud.r-project.org')"
        Rscript -e "remotes::install_github('carmonalab/scIntegrationMetrics', upgrade='never', lib='\${R_LIB_TMP}')"
        export R_LIBS="/usr/local/lib/R/site-library:\${R_LIB_TMP}"
    fi
    Rscript "${metric_script}"
    """

    stub:
    """
    echo 'sample_id,reduction,metric,status' > ${meta.id}_${reduction}_asw.csv
    echo '${meta.id},${reduction},asw,stub' >> ${meta.id}_${reduction}_asw.csv
    echo 'cell_barcode,batch_asw,celltype_asw,batch,celltype' > ${meta.id}_${reduction}_asw_cells.csv
    echo 'stub_cell,0.0,0.5,stub_batch,stub_ct' >> ${meta.id}_${reduction}_asw_cells.csv
    """
}
