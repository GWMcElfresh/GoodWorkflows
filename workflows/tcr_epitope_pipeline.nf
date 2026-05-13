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
    // Parsed once. meta propagates through INGEST_* → QUANTIFY_TCR with all
    // keys (including epitope_file), so no .join() is needed downstream.
    def ch_samples = parseTcrEpitopeSamplesheet(samplesheet)

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
        .mix(INGEST_FILE(ch_branched.file.map { m -> tuple(m, file(m.path)) }).rds)

    // ── 4. Propagate ingested RDS to QUANTIFY_TCR ───────────────────────
    // Meta already has epitope_file from the INGEST_* processes.
    // ch_ingested = (meta_with_epitope_file, rds_path) — no .join() needed.
    def ch_with_epi = ch_ingested

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
    // Uses clone_embeddings_umap emit (separate from _pred to avoid channel conflict).
    def leiden_res = params.tcr_umap_resolution ?: 0.5
    TCR_UMAP(EMBED_CLONES.out.clone_embeddings_umap, leiden_res)

    // ── 10. PREDICT_BINDING — per-sample clone × peptide score matrix ─────────
    // Uses clone_embeddings_pred emit (separate from _umap to avoid channel conflict).
    def model_path = file(params.binding_model_path ?: "${projectDir}/stub_binding_model")
    PREDICT_BINDING(
        ch_meta_rds
            .map { meta, tcr_csv, seurat_rds -> tuple(meta, seurat_rds) }
            // .combine() flattens tuples: (meta, seurat_rds) + (clone_emb) → 3-element tuple.
            // Destructure directly in the closure.
            .combine(EMBED_CLONES.out.clone_embeddings_pred)
            .map { meta, seurat_rds, clone_emb_file ->
                tuple(meta, clone_emb_file, file(meta.epitope_file), model_path)
            }
    )
    // PREDICT_BINDING.out.binding_scores      = (meta, parquet)  — clone × peptide matrix
    // PREDICT_BINDING.out.cell_binding_scores = (meta, parquet)  — one row per cell

    // ── 11. JOIN_SEURAT — attach clone results to original Seurat RDS ──────
    // Per sample: seurat_rds (from ch_meta_rds)
    // Global (broadcast to all samples): clone_metadata.csv, binding_scores.parquet
    //
    // TCR_UMAP.out.clone_metadata emits (meta, file) where meta.id = workflow id (not sample)
    // Capture outputs before closures to avoid DataflowVariable capture issues.
    // Use .set{} to bind process outputs to resolvable named channels.
    TCR_UMAP.out.clone_metadata.set { tcr_umap_meta_ch }
    PREDICT_BINDING.out.binding_scores.set { pb_binding_ch }
    // Build per-sample tuples for JOIN_SEURAT:
    // (meta_with_seurat_rds, seurat_rds, clone_metadata, binding_scores)
    //
    // ch_meta_rds is per-sample. pb_binding_ch and tcr_umap_meta_ch are workflow-level
    // (one file total). .combine() pairs every sample with the same file — which is
    // exactly what we want (broadcast the global file to all samples).
    // No DataflowVariable is captured in any closure.
    def ch_join_seurat = ch_meta_rds
        .map { meta, tcr_csv, seurat_rds -> tuple(meta, seurat_rds) }
        .combine(pb_binding_ch.map { m, f -> f })
        .combine(TCR_UMAP.out.clone_metadata)
        .map { meta, seurat_rds, binding_file, clone_meta_file ->
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
    clone_embeddings    = EMBED_CLONES.out.clone_embeddings_umap
    binding_scores      = PREDICT_BINDING.out.binding_scores
    cell_binding_scores = PREDICT_BINDING.out.cell_binding_scores
    clone_metadata      = TCR_UMAP.out.clone_metadata
    annotated_rds       = JOIN_SEURAT.out.seurat_annotated
}