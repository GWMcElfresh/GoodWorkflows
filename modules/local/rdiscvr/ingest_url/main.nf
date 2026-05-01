/*
 * Process: INGEST_URL
 *
 * Downloads a data file from a public URL (meta.url) and infers the file type
 * from the URL suffix. Supports:
 *   .rds  — Seurat RDS object (readRDS)
 *   .csv  — CSV/TSV table via data.table::fread (auto-detects delimiter)
 *   .tsv  — Same as CSV path
 *   .txt  — Same as CSV path (tab-delimited assumed unless comma-heavy)
 *
 * Falls back to readRDS() for unknown suffixes and catches errors gracefully.
 * Uses the rdiscvr container image for data.table dependency.
 * No LabKey, .netrc, or Rdiscvr library dependencies.
 */

process INGEST_URL {
    tag 'ingest_url'
    label 'process_ingest_url'

    container 'ghcr.io/bimberlabinternal/rdiscvr:latest'

    publishDir "${params.outdir}/ingest", mode: 'copy'

    input:
    val(meta)

    output:
    tuple val(meta), path("${meta.id}.rds"), emit: rds
    tuple val(meta), path("${meta.id}_metadata.csv"), emit: metadata

    script:
    template 'ingest_url.r'

    stub:
    """
    touch "${meta.id}.rds"
    touch "${meta.id}_metadata.csv"
    """
}