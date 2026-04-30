nextflow.enable.dsl = 2

include { INGEST_METADATA } from '../modules/local/rdiscvr/ingest_metadata/main.nf'
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
            }
            if (hasUrl) {
                meta.url = row.url.toString()
            }

            meta
        }
}

/**
 * Metadata-only workflow entrypoint.
 *
 * Downloads cell-level metadata tables from LabKey and aggregates them into a
 * subject-level summary table suitable for cohort QC and downstream analysis.
 */
workflow INGEST_TABULATE_PIPELINE {
    take:
    samplesheet

    main:
    ch_samples = buildIngestTabulateSamplesChannel(samplesheet)

    INGEST_METADATA(ch_samples)

    ch_metadata_csvs = INGEST_METADATA.out.metadata
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
    metadata = INGEST_METADATA.out.metadata
    subject_table = TABULATE.out.subject_table
}
