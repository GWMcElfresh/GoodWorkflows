nextflow.enable.dsl = 2

include { INGEST_METADATA } from '../modules/local/rdiscvr/ingest_metadata/main.nf'
include { INGEST_URL } from '../modules/local/rdiscvr/ingest_url/main.nf'
include { TABULATE } from '../modules/local/rdiscvr/tabulate/main.nf'

/**
 * Build the samplesheet-derived metadata channel for the metadata-only path.
 *
 * The samplesheet must define one row per sample with the columns
 * `sample_id`, `species`, and either `output_file_id` (LabKey mode) or `url` (public download mode).
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

            if (!hasOutputFileId && !hasUrl) {
                error "Samplesheet row must have either 'output_file_id' (LabKey mode) or 'url' (public download mode): ${row}"
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
                meta.mode = meta.mode ?: 'url'
            }

            meta
        }
}

/**
 * Metadata-only workflow entrypoint.
 *
 * Downloads cell-level metadata tables and aggregates them into a
 * subject-level summary table suitable for cohort QC and downstream analysis.
 * Supports both LabKey (output_file_id) and URL-based (public RDS) modes.
 */
workflow INGEST_TABULATE_PIPELINE {
    take:
    samplesheet

    main:
    ch_samples = buildIngestTabulateSamplesChannel(samplesheet)

    // Branch: LabKey (output_file_id) vs URL (public download)
    ch_labkey = ch_samples.branch { meta ->
        labkey: meta.mode == 'labkey'
        url:    meta.mode == 'url'
    }

    // LabKey mode: INGEST_METADATA uses Rdiscvr to download metadata directly
    ch_labkey_metadata = INGEST_METADATA(ch_labkey.labkey).metadata

    // URL mode: INGEST_URL downloads the full Seurat object and extracts metadata
    ch_url_metadata = INGEST_URL(ch_labkey.url).metadata

    ch_metadata_csvs = ch_labkey_metadata
        .mix(ch_url_metadata)
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
    metadata = ch_labkey_metadata.mix(ch_url_metadata)
    subject_table = TABULATE.out.subject_table
}
