/*
 * Process: INGEST_FILE
 *
 * Copies a Seurat object from a local filesystem path, then reads and validates it.
 *
 * This is the local-file counterpart to INGEST_LABKEY (LabKey/Prime-seq) and
 * INGEST_URL (HTTP/HTTPS URLs). Use INGEST_FILE when samplesheet rows have a
 * non-empty 'path' column pointing to a local .rds (or .h5ad, .csv, .tsv, .txt) file.
 *
 * Requires no network access and no authentication. The file must exist at the
 * specified path before the process runs.
 */

process INGEST_FILE {
    tag 'ingest_file'
    label 'process_ingest_file'

    container 'ghcr.io/bimberlabinternal/rdiscvr:latest'

    publishDir "${params.outdir}/ingest", mode: 'copy'

    input:
    tuple val(meta), path(source_file)

    output:
    tuple val(meta), path("${meta.id}.rds"), emit: rds
    tuple val(meta), path("${meta.id}_metadata.csv"), emit: metadata

    script:
    template 'ingest_file.r'

    stub:
    """
    touch "${meta.id}.rds"
    touch "${meta.id}_metadata.csv"
    """
}