nextflow.enable.dsl = 2

include { INGEST_METADATA } from '../modules/local/rdiscvr/ingest_metadata/main.nf'
include { INGEST_METADATA_FILE } from '../modules/local/rdiscvr/ingest_metadata_file/main.nf'
include { INGEST_URL } from '../modules/local/rdiscvr/ingest_url/main.nf'
include { INGEST_FILE } from '../modules/local/rdiscvr/ingest_file/main.nf'
include { TABULATE } from '../modules/local/rdiscvr/tabulate/main.nf'

/**
 * Build the samplesheet-derived metadata channel for the metadata-only path.
 *
 * The samplesheet must define one row per sample with the columns
 * `sample_id`, `species`, and one of `output_file_id` (LabKey mode), `url`
 * (public download mode), `path` (local-file mode), or `metadata_path` (metadata CSV mode).
 *
 * @param samplesheetPath Path to the input samplesheet CSV file.
 * @return Channel emitting one metadata map per sample.
 */
def buildIngestTabulateSamplesChannel(samplesheetPath) {
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
            def hasMetadataPath = row.containsKey('metadata_path') && row.metadata_path?.trim()

            def modeCount = ([hasOutputFileId, hasUrl, hasPath, hasMetadataPath].count { it }) as int
            if (modeCount == 0) {
                error "Samplesheet row must have one of 'output_file_id' (LabKey), 'url' (download), 'path' (local file), or 'metadata_path' (metadata CSV): ${row}"
            }
            if (modeCount > 1) {
                error "Samplesheet row must have exactly ONE of 'output_file_id', 'url', 'path', or 'metadata_path' (found ${modeCount}): ${row}"
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
            if (hasMetadataPath) {
                meta.metadata_path = row.metadata_path.toString()
                meta.mode = 'metadata'
            }

            meta
        }
}

/**
 * Metadata-only workflow entrypoint.
 *
 * Downloads cell-level metadata tables and aggregates them into a
 * subject-level summary table suitable for cohort QC and downstream analysis.
 * Supports LabKey (output_file_id), URL-based (public RDS), local-file mode,
 * and direct metadata CSV mode (metadata_path).
 */
workflow INGEST_TABULATE_PIPELINE {
    take:
    samplesheet

    main:
    ch_samples = buildIngestTabulateSamplesChannel(samplesheet)

    ch_labkey = ch_samples.branch { meta ->
        labkey:   meta.mode == 'labkey'
        url:      meta.mode == 'url'
        file:     meta.mode == 'file'
        metadata: meta.mode == 'metadata'
    }

    // LabKey mode: INGEST_METADATA uses Rdiscvr to download metadata directly
    ch_labkey_metadata = INGEST_METADATA(ch_labkey.labkey).metadata

    // URL mode: INGEST_URL downloads the full Seurat object and extracts metadata
    ch_url_metadata = INGEST_URL(ch_labkey.url).metadata

    // Local file mode: INGEST_FILE copies the Seurat object and extracts metadata
    ch_file_metadata = INGEST_FILE(ch_labkey.file.map { meta -> [meta, file(meta.path)] }).metadata

    // Metadata CSV mode: INGEST_METADATA_FILE reads a metadata CSV directly
    ch_metadata_metadata = INGEST_METADATA_FILE(ch_labkey.metadata.map { meta -> [meta, file(meta.metadata_path)] }).metadata

    ch_metadata_csvs = ch_labkey_metadata
        .mix(ch_url_metadata)
        .mix(ch_file_metadata)
        .mix(ch_metadata_metadata)
        .map { _meta, metadata_csv -> metadata_csv }
        .collect()

    TABULATE(
        ch_metadata_csvs,
        params.tabulate_id_cols,
        params.tabulate_celltype_cols,
        params.tabulate_parent_col,
        params.tabulate_celltype_parent_map
    )

    emit:
    metadata = ch_labkey_metadata.mix(ch_url_metadata).mix(ch_file_metadata).mix(ch_metadata_metadata)
    subject_table = TABULATE.out.subject_table
}
