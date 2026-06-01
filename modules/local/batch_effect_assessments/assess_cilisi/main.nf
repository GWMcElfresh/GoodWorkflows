process ASSESS_CILISI {
    tag 'assess-cilisi'
    label 'process_tabulate'

    container { params.goodworkflows_container }

    input:
    tuple val(meta), path(rds), path(prep_json), val(reduction), path(batch_metrics_utils), path(metric_script)

    output:
    tuple val(meta), val(reduction), path("${meta.id}_${reduction}_cilisi.csv"), emit: metrics

    script:
    def outCsv = "${meta.id}_${reduction}_cilisi.csv"
    """
    #!/usr/bin/env bash
    set -euo pipefail
    export RDS_PATH="${rds}"
    export PREP_JSON="${prep_json}"
    export REDUCTION='${reduction}'
    export OUT_CSV="${outCsv}"
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
    echo 'sample_id,reduction,metric,status' > ${meta.id}_${reduction}_cilisi.csv
    echo '${meta.id},${reduction},cilisi,stub' >> ${meta.id}_${reduction}_cilisi.csv
    """
}
