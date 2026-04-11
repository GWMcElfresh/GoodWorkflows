nextflow.enable.dsl = 2

include { INGEST } from '../../modules/local/rdiscvr/ingest/main.nf'

workflow {
    def meta = [
        id: 'TEST_SAMPLE',
        output_file_id: '100001',
        species: 'human'
    ]

    INGEST(Channel.of(tuple(meta)))
}
