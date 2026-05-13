/*
 * Process: JOIN_SEURAT
 *
 * Joins clone-level TCR epitope results back to the original Seurat RDS
 * by clonotype_id (fallback to TRA|TRB seq hash if clonotype_id missing).
 *
 * Inputs:
 *   - seurat_rds:       original Seurat RDS from QUANTIFY_TCR
 *   - clone_metadata:   clone_metadata.parquet (clonotype_id, umap_x, umap_y, cluster, n_cells)
 *   - binding_scores:   binding_scores.parquet (clone_id, pep_XXX_score, …)
 *                       Columns = epitope names from the sample's epitope pool.
 *
 * Produces:
 *   - annotated RDS with new metadata columns:
 *       tcr_umap_x, tcr_umap_y, tcr_cluster, tcr_n_cells
 *       pep_<NAME>_score for each peptide in the sample's epitope pool
 *       Cells without TCRs get NA for all tcr_* columns.
 *
 * Join key: clonotype_id (from Seurat TCR metadata, set by tcrClustR).
 * Fallback:  SHA256(TRA_SEQ || "|" || TRB_SEQ) if clonotype_id is NA.
 *
 * Container: milton_tcr_container (R + Seurat + arrow)
 */

process JOIN_SEURAT {
    tag 'join-seurat'
    label 'process_small'

    container "${params.milton_tcr_container}"

    publishDir "${params.outdir}/tcr_epitope", mode: 'copy'

    input:
    tuple val(meta), path(seurat_rds), path(clone_metadata), path(binding_scores)

    output:
    tuple val(meta), path("${meta.id}_annotated.rds"), emit: seurat_annotated

    script:
    template 'join_seurat.R'

    stub:
    """
    touch "${meta.id}_annotated.rds"
    """
}