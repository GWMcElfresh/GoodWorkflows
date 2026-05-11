/*
 * Process: TRAIN_GEX_MIL
 *
 * Runs mil-ton's scVI + attention-MIL pipeline on a merged GEX AnnData file.
 *
 * Stages:
 *   1. Train scVI  -> adata.obsm['X_scVI']
 *   2. Train MIL   -> model.pt  (attention-MIL with GatedAttention)
 *   3. Predict     -> predictions.csv
 *   4. Saliency    -> attention_weights.csv  (per-cell attention scores)
 */

process TRAIN_GEX_MIL {
    tag 'train-gex-mil'
    label 'process_gpu'

    container "${params.milton_container}"

    publishDir "${params.outdir}/gex_mil", mode: 'copy'

    input:
    path merged_h5ad
    path cell_metadata

    output:
    path('scvi_model/'),           emit: scvi_model
    path('model.pt'),              emit: mil_model
    path('config.yaml'),           emit: config
    path('metrics.json'),          emit: metrics
    path('predictions.csv'),        emit: predictions
    path('attention_weights.csv'),  emit: attention

    script:
    template 'train_gex_mil.py'

    stub:
    """
    mkdir -p scvi_model
    touch scvi_model/model.pt
    touch model.pt
    touch config.yaml
    printf '{"test":{}}\\n' > metrics.json
    printf 'donor,pred,prob\\n' > predictions.csv
    printf 'donor,cell_barcode,attention\\n' > attention_weights.csv
    """
}
