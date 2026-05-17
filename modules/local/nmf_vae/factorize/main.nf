/*
 * Process: NMF_VAE_FACTORIZE
 *
 * Runs NMF-VAE factorization on a joint count matrix using nmfvae-train.
 * Consumes the merged .h5ad and genes.txt from NMF_VAE_MERGE_COUNTS.
 */

process NMF_VAE_FACTORIZE {
    tag 'nmf-vae-factorize'
    label 'process_nmf_vae'

    container { params.nmfvae_container }

    publishDir "${params.outdir}/nmf_vae", mode: 'copy'

    input:
    path merged_h5ad
    path genes_file
    val lambda_graph

    output:
    path('latent_Z.csv'),        emit: latent_z
    path('decoder_W.csv'),       emit: decoder_w
    path('loss_history.csv'),    emit: loss_history
    path('loss.png'),            emit: loss_plot
    path('model_checkpoint.pt'), emit: model_checkpoint
    path('*_laplacian.npy'),     emit: laplacian

    script:
    template 'factorize.sh'

    stub:
    """
    touch latent_Z.csv
    touch decoder_W.csv
    touch loss_history.csv
    touch loss.png
    touch model_checkpoint.pt
    touch dummy_laplacian.npy
    """
}
