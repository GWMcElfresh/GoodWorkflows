nextflow.enable.dsl = 2

include { INGEST } from '../modules/local/rdiscvr/ingest/main.nf'
include { EXPORT_COUNTS } from '../modules/local/cellmembrane/seurat/main.nf'
include { GENE_HARMONIZE } from '../modules/local/gene_harmonize/main.nf'
include { SCMODAL_INTEGRATE } from '../modules/local/nmf_vae/gpu/main.nf'

def buildFullPipelineSamplesChannel(samplesheetPath) {
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

workflow FULL_PIPELINE {
    take:
    samplesheet

    main:
    def execName = (session?.config?.executor?.name ?: workflow.profile ?: 'local').toString()
    if (execName == 'local') {
        error """
        The 'full' workflow requires a GPU (SCMODAL_INTEGRATE) and cannot run with the local executor.
        Use --workflow ingest_tabulate or --workflow ingest_export for local/Mac testing.
        Run with -profile slurm on HPC for the full pipeline.
        """.stripIndent()
    }
    ch_samples = buildFullPipelineSamplesChannel(samplesheet)

    INGEST(ch_samples)
    EXPORT_COUNTS(INGEST.out.rds)

    ch_all_count_dirs = EXPORT_COUNTS.out.counts_dir
        .map { _meta, count_dir -> count_dir }
        .collect()

    GENE_HARMONIZE(ch_all_count_dirs)
    SCMODAL_INTEGRATE(GENE_HARMONIZE.out.harmonized)

    GENE_HARMONIZE.out.harmonized.subscribe { log.info "Harmonized species outputs staged: ${it}" }

    emit:
    rds = INGEST.out.rds
    counts = EXPORT_COUNTS.out.counts_dir
    harmonized = GENE_HARMONIZE.out.harmonized
    model = SCMODAL_INTEGRATE.out.model
}
