/*
 * Process: TRAIN_TCR_MIL
 *
 * Runs mil-ton's BertTCR CNN-MIL pipeline on TCR clone data.
 *
 * Stages:
 *   1. Build donor-level MIL bags from CDR3 sequences (top-N by CloneSize)
 *   2. Encode CDR3s with ProtBERT (Rostlab/prot_bert_bfd, 1024-dim)
 *   3. Train BertTCRModel (CNN kernels 2/3/4, 5-head MIL ensemble)
 *   4. Predict + saliency -> top informative TCRs per donor
 */

process TRAIN_TCR_MIL {
    tag 'train-tcr-mil'
    label 'process_gpu'

    container { params.milton_container }

    publishDir "${params.outdir}/tcr_mil", mode: 'copy'

    input:
    path tcr_metadata_csv

    output:
    path('tcr_model.pt'),           emit: tcr_model
    path('tcr_history.json'),       emit: tcr_history
    path('tcr_predictions.csv'),    emit: tcr_predictions
    path('tcr_importance.csv'),      emit: tcr_importance

    script:
    template 'train_tcr_mil.py'

    stub:
    """
    touch tcr_model.pt
    printf '{}' > tcr_history.json
    printf 'donor,pred,prob\\n' > tcr_predictions.csv
    printf 'donor,CDR3,importance\\n' > tcr_importance.csv
    """
}
