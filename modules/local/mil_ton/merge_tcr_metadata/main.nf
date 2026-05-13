/*
 * Process: MERGE_TCR_METADATA
 *
 * Concatenates per-sample tcrClustR metadata CSVs into a single CSV
 * for the TRAIN_TCR_MIL Python step.
 */

process MERGE_TCR_METADATA {
    tag 'merge-tcr-metadata'
    label 'process_small'

    container { params.milton_container }

    publishDir "${params.outdir}/tcr_quant", mode: 'copy'

    input:
    path tcr_csvs

    output:
    path('merged_tcr_metadata.csv'), emit: merged_csv

    script:
    """
    head -n 1 ${tcr_csvs[0]} > merged_tcr_metadata.csv
    for f in ${tcr_csvs.join(' ')}; do
        tail -n +2 "\$f" >> merged_tcr_metadata.csv
    done
    wc -l merged_tcr_metadata.csv
    """

    stub:
    """
    printf 'barcode,SubjectId,TRA_CloneIdx,TRA_CloneSize\\n' > merged_tcr_metadata.csv
    """
}
