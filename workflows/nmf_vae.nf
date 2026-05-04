nextflow.enable.dsl = 2

include { INGEST_LABKEY } from '../modules/local/rdiscvr/ingest_labkey/main.nf'
include { INGEST_URL } from '../modules/local/rdiscvr/ingest_url/main.nf'
include { INGEST_FILE } from '../modules/local/rdiscvr/ingest_file/main.nf'
include { EXPORT_COUNTS } from '../modules/local/cellmembrane/seurat/main.nf'
include { NMF_VAE_MERGE_COUNTS } from '../modules/local/nmf_vae/merge_counts/main.nf'
include { NMF_VAE_FACTORIZE } from '../modules/local/nmf_vae/factorize/main.nf'

/**
 * Build the metadata channel consumed by the NMF-VAE workflow.
 *
 * The samplesheet must define one row per sample with the columns
 * `sample_id`, `species`, `lambda_graph`, and one of `output_file_id`
 * (LabKey mode), `url` (public download mode), or `path` (local-file mode).
 *
 * @param samplesheetPath Path to the input samplesheet CSV file.
 * @return Channel emitting one metadata map per sample.
 */
def buildNmfVaeSamplesChannel(samplesheetPath) {
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
                id:           row.sample_id.toString(),
                species:      row.species.toString(),
                lambda_graph: row.containsKey('lambda_graph') && row.lambda_graph?.trim()
                             ? row.lambda_graph.toString()
                             : null
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
 * NMF-VAE pipeline entrypoint.
 *
 * Downloads Seurat objects, exports raw counts, merges them into a joint
 * .h5ad matrix, and trains an NMF-VAE with signed graph Laplacian
 * regularization (ARCHS4 correlation) to produce shared gene programs.
 * This workflow runs on CPU or GPU depending on the executor profile.
 */
workflow NMF_VAE_PIPELINE {
    take:
    samplesheet

    main:
    if (!params.local_gpu && workflow.profile == 'local') {
        log.warn """
        WARNING: NMF_VAE_PIPELINE is running on the 'local' profile without a GPU.
        NMF-VAE will fall back to CPU execution, which may be slow for large datasets.
        Use -profile local_gpu for accelerated GPU execution if available.
        """.stripIndent()
    }

    ch_samples = buildNmfVaeSamplesChannel(samplesheet)

    // Determine lambda_graph: first non-null from samplesheet, else param fallback.
    // Since this is a joint factorization, we need a single value.
    ch_lambda_graph = ch_samples
        .map { it.lambda_graph }
        .filter { it != null && it.toString() != 'null' }
        .first()
        .map { it -> it ? it : params.nmf_vae_lambda_graph }

    ch_labkey = ch_samples.branch { meta ->
        labkey: meta.mode == 'labkey'
        url:    meta.mode == 'url'
        file:   meta.mode == 'file'
    }

    ch_ingested_rds = INGEST_LABKEY(ch_labkey.labkey).rds
        .mix(INGEST_URL(ch_labkey.url).rds)
        .mix(INGEST_FILE(ch_labkey.file.map { meta -> [meta, file(meta.path)] }).rds)

    EXPORT_COUNTS(ch_ingested_rds)

    ch_all_count_dirs = EXPORT_COUNTS.out.counts_dir
        .map { _meta, count_dir -> count_dir }
        .collect()

    NMF_VAE_MERGE_COUNTS(ch_all_count_dirs)

    NMF_VAE_FACTORIZE(
        NMF_VAE_MERGE_COUNTS.out.merged_h5ad,
        NMF_VAE_MERGE_COUNTS.out.genes_file,
        ch_lambda_graph
    )

    emit:
    counts = EXPORT_COUNTS.out.counts_dir
    merged_h5ad = NMF_VAE_MERGE_COUNTS.out.merged_h5ad
    genes_file = NMF_VAE_MERGE_COUNTS.out.genes_file
    latent_z = NMF_VAE_FACTORIZE.out.latent_z
    decoder_w = NMF_VAE_FACTORIZE.out.decoder_w
    loss_history = NMF_VAE_FACTORIZE.out.loss_history
    loss_plot = NMF_VAE_FACTORIZE.out.loss_plot
    model_checkpoint = NMF_VAE_FACTORIZE.out.model_checkpoint
}
