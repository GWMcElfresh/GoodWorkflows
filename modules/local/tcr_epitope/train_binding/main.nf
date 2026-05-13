/*
 * Process: TRAIN_TCR_EPITOPE
 *
 * One-shot trainer for the ESM-2 + XGBoost TCR-epitope binding model.
 * Downloads TCREpitopeBinding benchmark data via tdc.multi_pred,
 * embeds all sequences with ESM-2, concatenates epitope_emb + tcr_emb,
 * fits StandardScaler per split, trains XGBClassifier(gpu_hist), and
 * saves xgboost_model.pkl + scaler.pkl + training_history.json.
 *
 * Produces:
 *   binding_model_dir/
 *     xgboost_model.pkl
 *     scaler.pkl
 *     epitopes.fasta      (unique epitope sequences from TDC)
 *     training_history.json
 *     run_params.json
 */

process TRAIN_TCR_EPITOPE {
    tag 'train-tcr-epitope'
    label 'process_gpu'

    container { params.milton_tcr_container }

    publishDir "${params.outdir}/tcr_epitope_models", mode: 'copy'

    input:
    val epitope_panel   // string — "ALL" or comma-separated epitope IDs (unused but available)

    output:
    path("xgboost_model.pkl"),  emit: xgb_model
    path("scaler.pkl"),         emit: scaler
    path("epitopes.fasta"),     emit: epitopes_fasta
    path("training_history.json"), emit: history

    script:
    template 'train_binding.py'

    stub:
    """
    mkdir -p tcr_epitope_models
    touch tcr_epitope_models/xgboost_model.pkl
    touch tcr_epitope_models/scaler.pkl
    touch tcr_epitope_models/epitopes.fasta
    touch tcr_epitope_models/training_history.json
    touch tcr_epitope_models/run_params.json
    """
}