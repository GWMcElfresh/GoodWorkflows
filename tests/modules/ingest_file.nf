nextflow.enable.dsl = 2

include { INGEST_FILE } from '../../modules/local/rdiscvr/ingest_file/main.nf'

workflow {
    meta = [
        id: 'TEST_SAMPLE',
        species: 'human',
        path: "${projectDir}/tests/fixtures/sample.rds"
    ]

    INGEST_FILE(Channel.of([meta, file(meta.path)]))
}