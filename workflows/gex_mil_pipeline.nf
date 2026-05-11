nextflow.enable.dsl = 2

// GoodWorkflows ingest + export modules (sibling directory)
include { INGEST_LABKEY } from '../modules/local/rdiscvr/ingest_labkey/main.nf'
include { INGEST_URL }    from '../modules/local/rdiscvr/ingest_url/main.nf'
include { INGEST_FILE }   from '../modules/local/rdiscvr/ingest_file/main.nf'
include { EXPORT_COUNTS } from '../modules/local/cellmembrane/seurat/main.nf'

// mil-ton modules
include { GEX_MERGE_COUNTS } from '../modules/local/mil_ton/gex_merge/main.nf'
include { TRAIN_GEX_MIL }   from '../modules/local/mil_ton/train_gex_mil/main.nf'

/*
 * Build the metadata channel for the GEX MIL pipeline.
 *
 * The samplesheet must define one row per sample with the columns
 * `sample_id`, `species`, and one of `output_file_id` (LabKey mode),
 * `url` (public download mode), or `path` (local-file mode).
 *
 * Additionally, the samplesheet should include a `SubjectId` column
 * that identifies the donor/subject for MIL bag construction.
 */
def buildGexMilSamplesChannel(samplesheetPath) {
    return Channel
        .fromPath(samplesheetPath, checkIfExists: true)
        .splitCsv(header: true, strip: true)
        .map { row ->
            ['sample_id', 'species', 'SubjectId'].each { column ->
                if (!row[column]) {
                    error "Samplesheet is missing required value for column '${column}': ${row}"
                }
            }

            def hasOutputFileId = row.containsKey('output_file_id') && row.output_file_id?.trim()
            def hasUrl          = row.containsKey('url')          && row.url?.trim()
            def hasPath         = row.containsKey('path')         && row.path?.trim()

            def modeCount = ([hasOutputFileId, hasUrl, hasPath].count { it }) as int
            if (modeCount == 0) {
                error "Samplesheet row must have one of 'output_file_id', 'url', or 'path': ${row}"
            }
            if (modeCount > 1) {
                error "Samplesheet row must have exactly ONE of 'output_file_id', 'url', or 'path': ${row}"
            }

            def meta = [
                id:        row.sample_id.toString(),
                species:    row.species.toString(),
                SubjectId:  row.SubjectId.toString()
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

/*
 * GEX MIL pipeline — donor-level classification from 10x gene-expression data.
 *
 *   INGEST_LABKEY / INGEST_URL / INGEST_FILE
 *          │                                          (Seurat RDS per sample)
 *          ▼
 *     EXPORT_COUNTS
 *          │                                          (10x counts per sample)
 *          ▼
 *     GEX_MERGE_COUNTS
 *          │                                          (merged GEX.h5ad + cell_metadata.csv)
 *          ▼
 *     TRAIN_GEX_MIL
 *          │                                          (scVI + attention-MIL)
 *          ▼
 *     scvi_model/, model.pt, metrics.json,
 *     predictions.csv, attention_weights.csv
 */
workflow GEX_MIL_PIPELINE {
    take:
    samplesheet

    main:
    if (!params.local_gpu && workflow.profile == 'local') {
        error """
        ERROR: GEX_MIL_PIPELINE requires a GPU but the 'local' profile is active.
        Use -profile local_gpu for local GPU execution, or -profile slurm_singularity for HPC.
        """
    }

    ch_samples = buildGexMilSamplesChannel(samplesheet)

    ch_labkey = ch_samples.branch { meta ->
        labkey: meta.mode == 'labkey'
        url:    meta.mode == 'url'
        file:   meta.mode == 'file'
    }

    // Tri-mode ingest → Seurat RDS
    ch_ingested_rds = INGEST_LABKEY(ch_labkey.labkey).rds
        .mix(INGEST_URL(ch_labkey.url).rds)
        .mix(INGEST_FILE(ch_labkey.file.map { meta -> [meta, file(meta.path)] }).rds)

    // Export to 10x-like counts
    EXPORT_COUNTS(ch_ingested_rds)

    // Merge per-sample counts into joint AnnData
    ch_count_dirs = EXPORT_COUNTS.out.counts_dir
        .map { _meta, count_dir -> count_dir }
        .collect()

    GEX_MERGE_COUNTS(ch_count_dirs)

    // Train scVI + attention-MIL
    TRAIN_GEX_MIL(
        GEX_MERGE_COUNTS.out.merged_h5ad,
        GEX_MERGE_COUNTS.out.cell_metadata,
    )

    emit:
    rds          = ch_ingested_rds
    counts       = EXPORT_COUNTS.out.counts_dir
    merged_gex   = GEX_MERGE_COUNTS.out.merged_h5ad
    cell_meta    = GEX_MERGE_COUNTS.out.cell_metadata
    scvi_model   = TRAIN_GEX_MIL.out.scvi_model
    mil_model    = TRAIN_GEX_MIL.out.mil_model
    config       = TRAIN_GEX_MIL.out.config
    metrics      = TRAIN_GEX_MIL.out.metrics
    predictions  = TRAIN_GEX_MIL.out.predictions
    attention    = TRAIN_GEX_MIL.out.attention
}
