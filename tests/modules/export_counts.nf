nextflow.enable.dsl = 2

include { EXPORT_COUNTS } from '../../modules/local/cellmembrane/seurat/main.nf'

workflow {
    def meta = [
        id: 'TEST_SAMPLE',
        output_file_id: '100001',
        species: 'human'
    ]
    def dummyRds = file("${baseDir}/../fixtures/sample.rds", checkIfExists: true)

    EXPORT_COUNTS(Channel.of(tuple(meta, dummyRds)))
}
