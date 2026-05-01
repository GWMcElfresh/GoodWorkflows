/*
 * Process: INGEST_LABKEY
 *
 * Downloads a Seurat object from LabKey/Prime-seq using Rdiscvr's
 * DownloadOutputFile() with .netrc authentication.
 *
 * This is the LabKey-only counterpart to INGEST_URL (HTTP/HTTPS URLs) and
 * INGEST_FILE (local filesystem paths). Use INGEST_LABKEY when samplesheet
 * rows have a non-empty 'output_file_id' column.
 */

process INGEST_LABKEY {
    tag 'ingest_labkey'
    label 'process_ingest_labkey'

    container 'ghcr.io/bimberlabinternal/rdiscvr:latest'

    publishDir "${params.outdir}/ingest", mode: 'copy'

    input:
    val(meta)

    output:
    tuple val(meta), path("${meta.id}.rds"), emit: rds
    tuple val(meta), path("${meta.id}_metadata.csv"), emit: metadata

    script:
    template 'ingest_labkey.r'

    stub:
    """
    touch "${meta.id}.rds"
    touch "${meta.id}_metadata.csv"
    """
}