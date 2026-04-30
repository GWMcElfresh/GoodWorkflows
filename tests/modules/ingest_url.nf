nextflow.enable.dsl = 2

include { INGEST_URL } from '../../modules/local/rdiscvr/ingest_url/main.nf'

workflow {
    meta = [
        id: 'TEST_SAMPLE',
        species: 'human',
        url: 'https://example.org/test.rds'
    ]

    INGEST_URL(Channel.of(meta))
}