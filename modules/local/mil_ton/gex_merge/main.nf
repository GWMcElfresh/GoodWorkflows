/*
 * Process: GEX_MERGE_COUNTS
 *
 * Merges per-sample 10x-like count matrix directories (from EXPORT_COUNTS)
 * into a single joint AnnData file and a matching cell-metadata CSV.
 * The merged .h5ad feeds mil-ton's scVI + attention-MIL pipeline.
 *
 * Uses CellMembrane::CreateSeuratObj / merge / Seurat-to-AnnData conversion.
 */

process GEX_MERGE_COUNTS {
    tag 'gex-merge-counts'
    label 'medium_job'

    container "${params.milton_container}"

    publishDir "${params.outdir}/gex", mode: 'copy'

    input:
    path count_dirs

    output:
    path('merged_gex.h5ad'),  emit: merged_h5ad
    path('cell_metadata.csv'), emit: cell_metadata

    script:
    template 'merge_gex.r'

    stub:
    """
    touch merged_gex.h5ad
    printf 'barcode,sample_id,SubjectId,disease_status\\n' > cell_metadata.csv
    """
}
