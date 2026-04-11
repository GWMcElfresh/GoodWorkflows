nextflow.enable.dsl = 2

include { SCMODAL_INTEGRATE } from '../../modules/local/nmf_vae/gpu/main.nf'

workflow {
    def harmonizedDir = file("${baseDir}/../fixtures/harmonized_inputs", checkIfExists: true)

    SCMODAL_INTEGRATE(Channel.of(harmonizedDir))
}
