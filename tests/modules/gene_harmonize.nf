nextflow.enable.dsl = 2

include { GENERATE_SYNTHETIC_COUNTS } from './helpers/synthetic_fixtures.nf'
include { GENE_HARMONIZE } from '../../modules/local/gene_harmonize/main.nf'

workflow {
    GENERATE_SYNTHETIC_COUNTS()

    GENE_HARMONIZE(GENERATE_SYNTHETIC_COUNTS.out.counts_dir)
}
