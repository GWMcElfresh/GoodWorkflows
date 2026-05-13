/*
 * Process: TCR_UMAP
 *
 * Performs Leiden clustering and UMAP projection on ESM-2 clone embeddings
 * for visualization. This step is UNSUPERVISED — it does not require epitope
 * or binding data; it operates purely on the TCR clone embedding space.
 *
 * Accepts:
 *   - clone_embeddings.parquet (from EMBED_CLONES)
 *   - leiden_resolution: parameter for Leiden clustering granularity
 *
 * Produces:
 *   - clone_metadata.parquet
 *       clonotype_id  (clone identifier from deduplication)
 *       umap_x, umap_y  (2D projection coordinates)
 *       cluster         (Leiden cluster assignment)
 *       n_cells         (count of cells belonging to this clone)
 *       embedding_*     (the ESM-2 embedding dimensions, for reference)
 *
 * The clone_metadata.parquet feeds JOIN_SEURAT, which joins these results
 * back to the original Seurat object on clonotype_id.
 */

process TCR_UMAP {
    tag 'tcr-umap'
    label 'process_lowcpu'

    container "${params.milton_tcr_container}"

    publishDir "${params.outdir}/tcr_epitope", mode: 'copy'

    input:
    path clone_embeddings_parquet
    val leiden_resolution

    output:
    path('clone_metadata.parquet'), emit: clone_metadata

    script:
    template 'tcr_umap.py'

    stub:
    """
    touch clone_metadata.parquet
    """
}