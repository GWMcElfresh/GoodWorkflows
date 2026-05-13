nextflow.enable.dsl = 2

// Tri-mode ingest — same module paths as GoodWorkflows
include { INGEST_LABKEY } from '../modules/local/rdiscvr/ingest_labkey/main.nf'
include { INGEST_URL }    from '../modules/local/rdiscvr/ingest_url/main.nf'
include { INGEST_FILE }   from '../modules/local/rdiscvr/ingest_file/main.nf'
include { QUANTIFY_TCR }       from '../modules/local/mil_ton/quantify_tcr/main.nf'
include { MERGE_TCR_METADATA } from '../modules/local/mil_ton/merge_tcr_metadata/main.nf'
include { TRAIN_TCR_MIL }     from '../modules/local/mil_ton/train_tcr_mil/main.nf'

/*
 * Build the metadata channel for the TCR MIL pipeline.
 *
 * The samplesheet must define one row per sample with the columns
 * `sample_id` and one of `output_file_id` (LabKey), `url`, or `path`.
 *
 * The Seurat object is expected to carry TCR columns:
 *   - SubjectId  (donor identity)
 *   - TRA / TRB  (CDR3 amino-acid sequences)
 *   - TRA_V / TRA_J / TRB_V / TRB_J  (V and J gene assignments)
 */
def buildTcrMilSamplesChannel(samplesheetPath) {
    return Channel
        .fromPath(samplesheetPath, checkIfExists: true)
        .splitCsv(header: true, strip: true)
        .map { row ->
            if (!row.sample_id) {
                error "Samplesheet is missing required value for column 'sample_id': ${row}"
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

            def meta = [ id: row.sample_id.toString() ]

            // Include species if present in the samplesheet (needed by INGEST_FILE)
            if (row.containsKey('species') && row.species?.trim()) {
                meta.species = row.species.toString()
            }

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
 * TCR MIL pipeline — donor-level classification from TCR repertoire sequencing.
 *
 *   INGEST_LABKEY / INGEST_URL / INGEST_FILE
 *          │                                          (Seurat RDS with TCR columns)
 *          ▼
 *     QUANTIFY_TCR
 *          │  [tcrClustR::CalculateTcrDistances]
 *          │  - Formats TRA/TRB + V/J metadata
 *          │  - Runs tcrdist3 via reticulate
 *          │  - Stamps CloneIdx / CloneSize on cell metadata
 *          │  - Stores distance matrices in seuratObj@misc$TCR_Distances
 *          ▼
 *     {id}_tcr.rds + {id}_tcr_metadata.csv
 *          │
 *          ▼
 *     MERGE_TCR_METADATA
 *          │  (concatenates per-sample CSVs into one)
 *          ▼
 *     merged_tcr_metadata.csv
 *          │
 *          ▼
 *     TRAIN_TCR_MIL
 *          │  [mil-ton BertTCR pipeline]
 *          │  - TCRSequenceDataset builds donor bags (top-N by CloneSize)
 *          │  - TCRBertEncoder encodes CDR3s (ProtBERT, 1024-dim)
 *          │  - BertTCRModel trains CNN-MIL ensemble (5 heads)
 *          ▼
 *     tcr_model.pt, tcr_history.json,
 *     tcr_predictions.csv, tcr_importance.csv
 */
workflow TCR_MIL_PIPELINE {
    take:
    samplesheet

    main:
    ch_samples = buildTcrMilSamplesChannel(samplesheet)

    ch_labkey = ch_samples.branch { meta ->
        labkey: meta.mode == 'labkey'
        url:    meta.mode == 'url'
        file:   meta.mode == 'file'
    }

    // Tri-mode ingest → Seurat RDS
    ch_ingested_rds = INGEST_LABKEY(ch_labkey.labkey).rds
        .mix(INGEST_URL(ch_labkey.url).rds)
        .mix(INGEST_FILE(ch_labkey.file.map { meta -> [meta, file(meta.path)] }).rds)

    // Quantify TCR clones with tcrClustR
    QUANTIFY_TCR(ch_ingested_rds)

    // Concatenate per-sample TCR CSVs for the Python MIL step
    ch_tcr_csvs = QUANTIFY_TCR.out.tcr_metadata
        .map { _meta, csv -> csv }
        .collect()

    MERGE_TCR_METADATA(ch_tcr_csvs)

    // Train BertTCR CNN-MIL
    TRAIN_TCR_MIL(MERGE_TCR_METADATA.out.merged_csv)

    emit:
    rds             = ch_ingested_rds
    tcr_rds         = QUANTIFY_TCR.out.tcr_rds
    tcr_metadata     = QUANTIFY_TCR.out.tcr_metadata
    merged_tcr_meta = MERGE_TCR_METADATA.out.merged_csv
    tcr_model       = TRAIN_TCR_MIL.out.tcr_model
    tcr_history     = TRAIN_TCR_MIL.out.tcr_history
    tcr_predictions = TRAIN_TCR_MIL.out.tcr_predictions
    tcr_importance  = TRAIN_TCR_MIL.out.tcr_importance
}
