/*
 * Process: EXPORT_COUNTS
 *
 * Extracts raw counts and cell metadata from a Seurat object into a 10x-like
 * matrix directory. The output is consumed by the Python harmonization step.
 */

process EXPORT_COUNTS {
    tag 'export-counts'
    label 'process_export'

    container 'ghcr.io/bimberlabinternal/cellmembrane:latest'

    publishDir "${params.outdir}/counts", mode: 'copy'

    input:
    tuple val(meta), path(rds)

    output:
    tuple val(meta), path("${meta.id}_counts"), emit: counts_dir

    script:
    template 'export_counts.r'

    stub:
    """
    mkdir -p "${meta.id}_counts"
    touch "${meta.id}_counts/matrix.mtx"
    touch "${meta.id}_counts/features.tsv"
    touch "${meta.id}_counts/barcodes.tsv"
    touch "${meta.id}_counts/obs_meta.csv"
    """
}