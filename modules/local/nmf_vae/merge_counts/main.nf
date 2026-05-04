/*
 * Process: NMF_VAE_MERGE_COUNTS
 *
 * Merges per-sample 10x-like count matrix directories into a single joint
 * .h5ad file and extracts a genes.txt file. Consumes EXPORT_COUNTS output.
 */

process NMF_VAE_MERGE_COUNTS {
    tag 'nmf-vae-merge-counts'
    label 'process_nmf_vae'

    container "${params.nmfvae_container}"

    publishDir "${params.outdir}/nmf_vae", mode: 'copy'

    input:
    path count_dirs

    output:
    path('merged_counts.h5ad'), emit: merged_h5ad
    path('genes.txt'),         emit: genes_file

    script:
    template 'merge_counts.py'

    stub:
    """
    touch merged_counts.h5ad
    printf 'GENE1\\nGENE2\\n' > genes.txt
    """
}
