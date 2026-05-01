/*
 * Process: GENE_HARMONIZE
 *
 * Reads per-sample counts directories, maps genes across supported species via
 * mygene HomoloGene records, collapses duplicate orthologs, normalizes each
 * species dataset, and writes one harmonized AnnData file per species.
 */

process GENE_HARMONIZE {
    tag 'gene-harmonize'
    label 'process_harmonize'

    container "${params.scmodal_container}"

    publishDir "${params.outdir}/harmonized", mode: 'copy'

    input:
    path count_dirs

    output:
    path('harmonized_outputs'), emit: harmonized

    script:
    template 'harmonize.py'

    stub:
    """
    mkdir -p harmonized_outputs
    touch harmonized_outputs/00_human_harmonized.h5ad
    touch harmonized_outputs/01_macaque_harmonized.h5ad
    touch harmonized_outputs/integration_manifest.csv
    touch harmonized_outputs/ortholog_mapping.csv
    touch harmonized_outputs/shared_genes.csv
    printf '2000\n' > harmonized_outputs/n_shared.txt
    """
}