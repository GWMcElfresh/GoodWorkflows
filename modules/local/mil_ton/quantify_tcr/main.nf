/*
 * Process: QUANTIFY_TCR
 *
 * Quantifies TCR clones from a Seurat object using tcrClustR:
 *   1. Formats metadata columns (TRA/TRB/TRG/TRD + V/J genes)
 *   2. Runs tcrdist3 via reticulate  -> clone-level distance matrices
 *   3. Stamps CloneIdx / CloneSize metadata back onto the Seurat object
 *   4. Optionally runs Dirichlet-clustering for exploratory analysis
 *
 * Accepts:
 *   - Per-sample RDS files from INGEST_LABKEY / INGEST_URL / INGEST_FILE
 *   - A merged Seurat RDS with a SubjectId column
 *
 * Produces:
 *   - Updated Seurat RDS with TCR distances in seuratObj@misc$TCR_Distances
 *   - Cell-metadata CSV with *_CloneIdx / *_CloneSize columns
 */

process QUANTIFY_TCR {
    tag 'quantify-tcr'
    label 'process_tcr'

    container { params.tcrClustR_container }

    publishDir "${params.outdir}/tcr_quant", mode: 'copy'

    input:
    tuple val(meta), path(rds)

    output:
    tuple val(meta), path("${meta.id}_tcr.rds"), emit: tcr_rds
    tuple val(meta), path("${meta.id}_tcr_metadata.csv"), emit: tcr_metadata

    script:
    template 'quantify_tcr.R'

    stub:
    """
    touch "${meta.id}_tcr.rds"
    printf 'barcode,SubjectId,TRA_CloneIdx,TRA_CloneSize,TRB_CloneIdx,TRB_CloneSize\\n' > "${meta.id}_tcr_metadata.csv"
    """
}
