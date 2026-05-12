nextflow.enable.dsl = 2

include { INGEST_LABKEY } from '../modules/local/rdiscvr/ingest_labkey/main.nf'
include { INGEST_URL }    from '../modules/local/rdiscvr/ingest_url/main.nf'
include { INGEST_FILE }   from '../modules/local/rdiscvr/ingest_file/main.nf'
include { QUANTIFY_TCR }       from '../modules/local/mil_ton/quantify_tcr/main.nf'
include { MERGE_TCR_METADATA } from '../modules/local/mil_ton/merge_tcr_metadata/main.nf'
include { EMBED_CLONES }      from '../modules/local/tcr_epitope/embed/main.nf'
include { PREDICT_BINDING }   from '../modules/local/tcr_epitope/predict_binding/main.nf'
include { TCR_UMAP }          from '../modules/local/tcr_epitope/tcr_umap/main.nf'
include { JOIN_SEURAT }       from '../modules/local/tcr_epitope/join_seurat/main.nf'

/*
 * Samplesheet format for tcr_epitope workflow:
 *
 *   sample_id,epitope_file,output_file_id|url|path
 *
 * Required:
 *   sample_id    — unique sample identifier
 *   epitope_file — path to per-sample epitope FASTA (peptide pool)
 *   path         — local Seurat RDS path
 *
 * Epitope pools are per-sample, enabling multi-peptide stimulus panels
 * common in infectious disease studies. Each sample can have a different
 * pool; all clones are scored against all peptides in their sample's pool.
 */

def parseTcrEpitopeSamplesheet(samplesheetPath) {
    Channel
        .fromPath(samplesheetPath, checkIfExists: true)
        .splitCsv(header: true, strip: true)
        .map { row ->
            if (!row.sample_id)    error "Samplesheet missing 'sample_id': ${row}"
            if (!row.epitope_file) error "Samplesheet missing 'epitope_file': ${row}"

            def hasOutId = row.containsKey('output_file_id') && row.output_file_id?.trim()
            def hasUrl   = row.containsKey('url')           && row.url?.trim()
            def hasPath  = row.containsKey('path')          && row.path?.trim()

            def modeCount = ([hasOutId, hasUrl, hasPath].count { it }) as int
            if (modeCount == 0) error "Row needs one of 'output_file_id', 'url', or 'path': ${row}"
            if (modeCount > 1)  error "Row needs exactly ONE of 'output_file_id', 'url', or 'path': ${row}"

            def meta = [ id: row.sample_id.toString(), epitope_file: row.epitope_file.toString() ]
            if (hasOutId) { meta.output_file_id = row.output_file_id.toString(); meta.mode = 'labkey' }
            if (hasUrl)   { meta.url            = row.url.toString();            meta.mode = 'url'    }
            if (hasPath)  { meta.path           = row.path.toString();           meta.mode = 'file'   }
            meta
        }
}

workflow TCR_EPITOPE_PIPELINE {
    take:
    samplesheet

    main:
    // ── 1. Parse samplesheet ────────────────────────────────────────────────
    ch_samples = parseTcrEpitopeSamplesheet(samplesheet)

    // ── 2. Branch by ingest mode ───────────────────────────────────────────
    def ch_branched = ch_samples.branch { meta ->
        labkey: meta.mode == 'labkey'
        url:    meta.mode == 'url'
        file:   meta.mode == 'file'
    }

    // ── 3. Ingest Seurat RDS per sample ───────────────────────────────────
    // INGEST_* emit (meta_with_rds_key, rds_path)
    def ch_ingested = INGEST_LABKEY(ch_branched.labkey).rds
        .mix(INGEST_URL(ch_branched.url).rds)
        .mix(INGEST_FILE(ch_branched.file.map { m -> [m, file(m.path)] }).rds)

    // ── 4. Re-associate epitope_file with ingested RDS via sample id ───────
    // ch_ingested meta keys: {id, mode, path, [rds_key]}
    // ch_samples meta keys:  {id, epitope_file, mode, [labkey/url/file fields]}
    // Join by 'id' so each sample gets its epitope_file attached to the ingested RDS
    def ch_with_epi = ch_ingested
        .map { meta, rds -> [meta.id, meta, rds] }
        .join(ch_samples.map { m -> [m.id, m] }, failOnDuplicate: true, failOnMismatch: true)
        .map { sid, ingested_meta, rds, sample_meta ->
            def merged = sample_meta + [rds: rds]
            [merged, rds]
        }
    // ch_with_epi = (meta with {id, epitope_file, mode, rds}, rds_path)

    // ── 5. QUANTIFY_TCR — tcrClustR clone quantification per sample ─────────
    // Input to QUANTIFY_TCR: (meta + rds, rds_path)
    QUANTIFY_TCR(ch_with_epi)
    // QUANTIFY_TCR.out.tcr_rds      = (meta, rds_path)
    // QUANTIFY_TCR.out.tcr_metadata = (meta, csv_path)

    // ── 6. Propagate seurat_rds alongside tcr_metadata for downstream ──────
    def ch_meta_rds = QUANTIFY_TCR.out.tcr_metadata
        .join(QUANTIFY_TCR.out.tcr_rds, failOnDuplicate: true)
    // ch_meta_rds = (meta, tcr_csv, seurat_rds)

    // ── 7. Merge per-sample TCR CSVs ───────────────────────────────────────
    def ch_tcr_csvs = ch_meta_rds.map { _m, csv, _r -> csv }.collect()
    MERGE_TCR_METADATA(ch_tcr_csvs)
    // MERGE_TCR_METADATA.out.merged_csv = path to merged CSV (all cells)

    // ── 8. EMBED_CLONES — global ESM-2 clone embeddings (one per unique TCR) ─
    // Clone embeddings are sequence-only; epitope pool does NOT affect them.
    // We run on merged CSV to get a single embedding per unique TRA+TRB combo.
    def stub_epi = params.epitope_fasta ?: "${projectDir}/stub_epitopes.fa"
    EMBED_CLONES(MERGE_TCR_METADATA.out.merged_csv, file(stub_epi))

    // ── 9. TCR_UMAP — unsupervised Leiden + UMAP on global clone space ─────
    // No epitope needed; cluster structure is purely in embedding space.
    def leiden_res = params.tcr_umap_resolution ?: 0.5
    TCR_UMAP(EMBED_CLONES.out.clone_embeddings, leiden_res)
    // TCR_UMAP.out.clone_metadata = (meta_with_id, parquet) — single global file

    // ── 10. PREDICT_BINDING — per-sample clone × peptide score matrix ─────────
    // binding_model_path must contain xgboost_model.pkl + scaler.pkl
    def model_path = file(params.binding_model_path ?: "${projectDir}/stub_binding_model")

    // Build per-sample input: (meta, clone_embeddings_path, epitope_file_path, model_dir)
    // clone_embeddings is a SINGLE global file — broadcast it to every sample.
    // epitope_file comes from each sample's row in ch_samples.
    def ch_pred_input = ch_meta_rds
        .map { meta, tcr_csv, seurat_rds -> [meta.id, meta, seurat_rds] }
        .join(ch_samples.map { m -> [m.id, m] }, failOnDuplicate: true)
        .map { sid, meta_tcr, seurat_rds, meta_epi ->
            def meta_final = meta_tcr + [epitope_file: meta_epi.epitope_file]
            [meta_final, seurat_rds]
        }
        .map { meta, seurat_rds ->
            tuple(
                meta,
                EMBED_CLONES.out.clone_embeddings,
                file(meta.epitope_file),
                model_path
            )
        }

    PREDICT_BINDING(ch_pred_input)
    // PREDICT_BINDING.out.binding_scores      = (meta, parquet)  — clone × peptide matrix
    // PREDICT_BINDING.out.cell_binding_scores = (meta, parquet)  — one row per cell

    // ── 11. JOIN_SEURAT — attach clone results to original Seurat RDS ──────
    // Per sample: seurat_rds (from ch_meta_rds)
    // Global (broadcast to all samples): clone_metadata.csv, binding_scores.parquet
    //
    // TCR_UMAP.out.clone_metadata emits (meta, file) where meta.id = workflow id (not sample)
// TCR_UMAP emits one global clone_metadata parquet — get the file path
    def clone_meta_file = TCR_UMAP.out.clone_metadata

    // PREDICT_BINDING emits per sample; we need the single global binding scores.
    // Since we ran PREDICT_BINDING per sample with different epitope pools,
    // the binding_scores output is per-sample — each sample's scores reflect its own pool.
    // For JOIN_SEURAT: use the per-sample binding_scores (each sample's pool scores its clones).
    //
    // Join strategy: per sample — (meta + seurat_rds, seurat_rds, clone_meta_file, binding_file)
    // clone_meta_file is broadcast (same global file for all samples)
    // binding_file is per-sample (each sample scored against its own epitope pool)
    def ch_join_seurat = ch_meta_rds
        .map { meta, tcr_csv, seurat_rds -> [meta.id, meta, seurat_rds] }
        .join(
            PREDICT_BINDING.out.binding_scores
                .map { m, f -> [m.id, f] },
            failOnDuplicate: true
        )
        .map { sid, meta, seurat_rds, binding_file ->
            tuple(
                meta + [seurat_rds: seurat_rds],
                seurat_rds,
                clone_meta_file,
                binding_file
            )
        }

    JOIN_SEURAT(ch_join_seurat)

    // ── Emit ────────────────────────────────────────────────────────────────
    emit:
    rds                 = ch_ingested
    tcr_rds             = QUANTIFY_TCR.out.tcr_rds
    tcr_metadata        = QUANTIFY_TCR.out.tcr_metadata
    merged_tcr_meta     = MERGE_TCR_METADATA.out.merged_csv
    clone_embeddings    = EMBED_CLONES.out.clone_embeddings
    binding_scores      = PREDICT_BINDING.out.binding_scores
    cell_binding_scores = PREDICT_BINDING.out.cell_binding_scores
    clone_metadata      = TCR_UMAP.out.clone_metadata
    annotated_rds       = JOIN_SEURAT.out.seurat_annotated
}