nextflow.enable.dsl = 2

include { INGEST } from '../modules/local/rdiscvr/ingest/main.nf'
include { EXPORT_COUNTS } from '../modules/local/cellmembrane/seurat/main.nf'
include { GENE_HARMONIZE } from '../modules/local/gene_harmonize/main.nf'
include { SCMODAL_INTEGRATE } from '../modules/local/scModal/gpu/main.nf'

/**
 * Build the metadata channel consumed by the integration multi-species workflow.
 *
 * The samplesheet must define one row per sample with the columns
 * `sample_id`, `species`, and either `output_file_id` (LabKey mode) or `url` (public download mode).
 *
 * @param samplesheetPath Path to the input samplesheet CSV file.
 * @return Channel emitting one metadata map per sample.
 */
def buildIntegrationPipelineSamplesChannel(samplesheetPath) {
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
 * Integration pipeline entrypoint.
 *
 * Downloads Seurat objects from LabKey, exports raw counts, harmonizes genes
 * across species, and trains scMODAL to create a shared latent embedding.
 * This workflow is GPU-backed and intended for SLURM execution.
 */
workflow INTEGRATION_PIPELINE {
    take:
    samplesheet

    main:
    if (params.scmodal_use_cpu) {
        if (!System.getenv('GITHUB_ACTIONS')) {
            log.warn """
            WARNING: --scmodal_use_cpu is true but GITHUB_ACTIONS env is not set.
            This flag is intended for GitHub Actions CI smoke tests only.
            SCMODAL_INTEGRATE will run its stub block; outputs have no scientific validity.
            """.stripIndent()
        }
    } else if (!params.local_gpu && workflow.profile == 'local') {
        error """
        ERROR: INTEGRATION_PIPELINE requires a GPU but the 'local' profile is active.
        Use -profile local_gpu for local GPU execution, or -profile slurm_singularity for HPC.
        To force CPU-only stub execution (CI only), use --scmodal_use_cpu true.
        """.stripIndent()
    }
    ch_samples = buildIntegrationPipelineSamplesChannel(samplesheet)

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
