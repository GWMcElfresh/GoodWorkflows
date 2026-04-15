nextflow.enable.dsl = 2

include { GENERATE_SYNTHETIC_HARMONIZED } from './helpers/synthetic_fixtures.nf'
include { SCMODAL_INTEGRATE } from '../../modules/local/nmf_vae/gpu/main.nf'

workflow {
    GENERATE_SYNTHETIC_HARMONIZED()

    SCMODAL_INTEGRATE(GENERATE_SYNTHETIC_HARMONIZED.out.harmonized)
}
