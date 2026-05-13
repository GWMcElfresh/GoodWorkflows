/*
 * Process: PREDICT_BINDING
 *
 * Predicts TCR-epitope binding using a trained XGBoost binary classifier.
 * For each TCR clone (from EMBED_CLONES) and each epitope in the sample's
 * epitope pool (FASTA):
 *   1. Concatenate epitope ESM-2 embedding + TCR ESM-2 embedding → feature vec
 *   2. Apply StandardScaler (pre-fit on training data)
 *   3. Predict binding_score (probability of binding) for each clone × peptide pair
 *
 * Accepts:
 *   - clone_embeddings.parquet   (from EMBED_CLONES, global clone embeddings)
 *   - epitope_fasta:             per-sample epitope FASTA (peptide pool)
 *   - binding_model_dir:          directory containing trained XGBoost model + scaler
 *
 * Produces:
 *   - binding_scores.parquet      (clone_id, epitope_0001, epitope_0002, …)
 *                                Each cell = probability score for clone × peptide.
 *   - cell_binding_scores.parquet (one row per cell, per-sample expansion)
 *                                barcode, clone_id, then pep scores per cell's clone.
 */

process PREDICT_BINDING {
    tag 'predict-binding'
    label 'process_lowcpu'

    container "${params.milton_tcr_container}"

    publishDir "${params.outdir}/tcr_epitope", mode: 'copy'

    input:
    tuple val(meta), path(clone_embeddings_parquet), path(epitope_fasta), path(binding_model_dir)

    output:
    tuple val(meta), path("${meta.id}_binding_scores.parquet"), emit: binding_scores
    tuple val(meta), path("${meta.id}_cell_binding_scores.parquet"), emit: cell_binding_scores

    script:
    template 'predict_binding.py'

    stub:
    """
    touch "${meta.id}_binding_scores.parquet"
    touch "${meta.id}_cell_binding_scores.parquet"
    """
}