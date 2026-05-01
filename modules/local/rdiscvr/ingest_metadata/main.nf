/*
 * Process: INGEST_METADATA
 *
 * Downloads sample metadata only from prime-seq / LabKey using Rdiscvr's
 * DownloadMetadataForSeuratObject() and writes a normalized per-sample CSV
 * for downstream tabulation. Authentication is expected to come from a
 * read-only .netrc mount.
 */

process INGEST_METADATA {
    tag 'ingest-metadata'
    label 'process_ingest'

    container 'ghcr.io/bimberlabinternal/rdiscvr:latest'

    publishDir "${params.outdir}/ingest", mode: 'copy'

    input:
    val(meta)

    output:
    tuple val(meta), path("${meta.id}_metadata.csv"), emit: metadata

    script:
    template 'ingest_metadata.r'

    stub:
    """
    printf 'cDNA_ID\n' > "${meta.id}_metadata.csv"
    """
}