nextflow.enable.dsl = 2

include { GENE_HARMONIZE } from '../../modules/local/gene_harmonize/main.nf'

workflow {
    def countDir = file("${baseDir}/../fixtures/sample_counts", checkIfExists: true)

    GENE_HARMONIZE(Channel.of(countDir))
}
