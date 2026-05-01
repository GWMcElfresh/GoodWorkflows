nextflow.enable.dsl = 2

include { INGEST_LABKEY } from '../../modules/local/rdiscvr/ingest_labkey/main.nf'

workflow {
    meta = [
        id: 'TEST_SAMPLE',
        species: 'human',
        output_file_id: '100001'
    ]

    INGEST_LABKEY(Channel.of(meta))
}