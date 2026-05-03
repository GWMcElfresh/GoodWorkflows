/*
 * Process: INGEST_METADATA_FILE
 *
 * Reads a per-sample metadata CSV file directly and validates it for downstream
 * tabulation. Unlike INGEST_METADATA (LabKey-only) and INGEST_FILE (extracts from
 * Seurat objects), this process accepts a standalone metadata CSV — useful for
 * testing and for workflows where metadata is available as a separate file.
 *
 * The metadata CSV must contain:
 *   - A 'cDNA_ID' column (required by TABULATE)
 *   - At least one RIRA cell-type column (RIRA_Immune.cellclass, RIRA_TNK_v2.cellclass,
 *     RIRA_Myeloid_v3.cellclass) or the workflow will fail at TABULATE.
 *
 * The process adds sample_id and species columns from the metadata map, then writes
 * the enriched CSV for downstream TABULATE consumption.
 */

process INGEST_METADATA_FILE {
    tag 'ingest-metadata-file'
    label 'process_ingest_file'

    container 'ghcr.io/bimberlabinternal/rdiscvr:latest'

    publishDir "${params.outdir}/ingest", mode: 'copy'

    input:
    tuple val(meta), path(metadata_file)

    output:
    tuple val(meta), path("${meta.id}_metadata.csv"), emit: metadata

    script:
    template 'ingest_metadata_file.r'

    stub:
    """
    printf 'cDNA_ID\n' > "${meta.id}_metadata.csv"
    """
}
