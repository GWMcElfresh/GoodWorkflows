/*
 * Process: SCMODAL_INTEGRATE
 *
 * Consumes harmonized species-level AnnData files, trains scMODAL, writes the
 * latent embedding, and clusters cells in scMODAL space with Leiden.
 */

process SCMODAL_INTEGRATE {
    label 'process_gpu'

    container "${params.scmodal_container}"

    publishDir "${params.outdir}/scmodal", mode: 'copy'

    input:
    path harmonized_dir

    output:
    path 'model_outputs/', emit: model

    script:
    template 'integrate.py'

    stub:
    """
    mkdir -p model_outputs
    touch model_outputs/ckpt.pth
    touch model_outputs/latent_clustered.h5ad
    touch model_outputs/training_history.csv
    touch model_outputs/gpu_info.txt
    touch model_outputs/run_summary.json
    """
}