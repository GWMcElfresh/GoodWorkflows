nextflow.enable.dsl = 2

include { INGEST_METADATA } from '../modules/local/rdiscvr/ingest_metadata/main.nf'
include { TABULATE } from '../modules/local/rdiscvr/tabulate/main.nf'

def buildIngestTabulateSamplesChannel(samplesheetPath) {
    return Channel
        .fromPath(samplesheetPath, checkIfExists: true)
        .splitCsv(header: true, strip: true)
        .map { row ->
            ['sample_id', 'output_file_id', 'species'].each { column ->
                if (!row[column]) {
                    error "Samplesheet is missing required value for column '${column}': ${row}"
                }
            }

            def meta = [
                id: row.sample_id.toString(),
                output_file_id: row.output_file_id.toString(),
                species: row.species.toString()
            ]

            meta
        }
}

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
