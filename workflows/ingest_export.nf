nextflow.enable.dsl = 2

include { INGEST } from '../modules/local/rdiscvr/ingest/main.nf'
include { EXPORT_COUNTS } from '../modules/local/cellmembrane/seurat/main.nf'

def buildIngestExportSamplesChannel(samplesheetPath) {
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

            tuple(meta)
        }
}

workflow INGEST_EXPORT_PIPELINE {
    take:
    samplesheet

    main:
    ch_samples = buildIngestExportSamplesChannel(samplesheet)

    INGEST(ch_samples)
    EXPORT_COUNTS(INGEST.out.rds)

    emit:
    rds = INGEST.out.rds
    counts = EXPORT_COUNTS.out.counts_dir
}
