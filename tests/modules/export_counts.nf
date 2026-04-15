nextflow.enable.dsl = 2

include { GENERATE_SYNTHETIC_RDS } from './helpers/synthetic_fixtures.nf'
include { EXPORT_COUNTS } from '../../modules/local/cellmembrane/seurat/main.nf'

workflow {
    def meta = [
        id: 'TEST_SAMPLE',
        output_file_id: '100001',
        species: 'human'
    ]

    GENERATE_SYNTHETIC_RDS()

    ch_input = GENERATE_SYNTHETIC_RDS.out.rds.map { syntheticRds ->
        tuple(meta, syntheticRds)
    }

    EXPORT_COUNTS(ch_input)
}
