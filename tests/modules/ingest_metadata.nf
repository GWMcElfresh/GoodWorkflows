nextflow.enable.dsl = 2

include { INGEST_METADATA } from '../../modules/local/rdiscvr/ingest_metadata/main.nf'

workflow {
    def meta = [
        id: 'TEST_SAMPLE',
        output_file_id: '100001',
        species: 'human'
    ]

    INGEST_METADATA(Channel.of(meta))
}