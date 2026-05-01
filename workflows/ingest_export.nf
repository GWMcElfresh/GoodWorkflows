nextflow.enable.dsl = 2

include { INGEST_LABKEY } from '../modules/local/rdiscvr/ingest_labkey/main.nf'
include { INGEST_URL } from '../modules/local/rdiscvr/ingest_url/main.nf'
include { INGEST_FILE } from '../modules/local/rdiscvr/ingest_file/main.nf'
include { EXPORT_COUNTS } from '../modules/local/cellmembrane/seurat/main.nf'

/**
 * Build the samplesheet-derived metadata channel for the ingest/export workflow.
 *
 * The samplesheet must define one row per sample with the columns
 * `sample_id`, `species`, and one of `output_file_id` (LabKey mode), `url`
 * (public download mode), or `path` (local-file mode).
 *
 * @param samplesheetPath Path to the input samplesheet CSV file.
 * @return Channel emitting one metadata map per sample.
 */
def buildIngestExportSamplesChannel(samplesheetPath) {
    return Channel
        .fromPath(samplesheetPath, checkIfExists: true)
        .splitCsv(header: true, strip: true)
        .map { row ->
            ['sample_id', 'species'].each { column ->
                if (!row[column]) {
                    error "Samplesheet is missing required value for column '${column}': ${row}"
                }
            }

            def hasOutputFileId = row.containsKey('output_file_id') && row.output_file_id?.trim()
            def hasUrl = row.containsKey('url') && row.url?.trim()
            def hasPath = row.containsKey('path') && row.path?.trim()

            def modeCount = ([hasOutputFileId, hasUrl, hasPath].count { it }) as int
            if (modeCount == 0) {
                error "Samplesheet row must have one of 'output_file_id' (LabKey), 'url' (download), or 'path' (local file): ${row}"
            }
            if (modeCount > 1) {
                error "Samplesheet row must have exactly ONE of 'output_file_id', 'url', or 'path' (found ${modeCount}): ${row}"
            }

            def meta = [
                id: row.sample_id.toString(),
                species: row.species.toString()
            ]

            if (hasOutputFileId) {
                meta.output_file_id = row.output_file_id.toString()
                meta.mode = 'labkey'
            }
            if (hasUrl) {
                meta.url = row.url.toString()
                meta.mode = 'url'
            }
            if (hasPath) {
                meta.path = row.path.toString()
                meta.mode = 'file'
            }

            meta
        }
}

/**
 * Download Seurat objects and export them as 10x-like count directories.
 *
 * This workflow is intended for fast local or CI validation when users want
 * count matrices without running cross-species harmonization or scMODAL.
 */
workflow INGEST_EXPORT_PIPELINE {
    take:
    samplesheet

    main:
    ch_samples = buildIngestExportSamplesChannel(samplesheet)

    ch_labkey = ch_samples.branch { meta ->
        labkey: meta.mode == 'labkey'
        url:    meta.mode == 'url'
        file:   meta.mode == 'file'
    }

    ch_ingested_rds = INGEST_LABKEY(ch_labkey.labkey).rds
        .mix(INGEST_URL(ch_labkey.url).rds)
        .mix(INGEST_FILE(ch_labkey.file).rds)

    EXPORT_COUNTS(ch_ingested_rds)

    emit:
    rds = ch_ingested_rds
    counts = EXPORT_COUNTS.out.counts_dir
}
