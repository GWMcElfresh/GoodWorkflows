nextflow.enable.dsl = 2

include { TABULATE } from '../../modules/local/rdiscvr/tabulate/main.nf'

workflow {
    def metadataCsv = file("${baseDir}/../fixtures/sample_metadata.csv", checkIfExists: true)

    TABULATE(
        Channel.of(metadataCsv),
        Channel.value('cDNA_ID,SubjectId,Vaccine,Timepoint,Tissue'),
        Channel.value('RIRA_Immune.cellclass,RIRA_TNK_v2.cellclass,RIRA_Myeloid_v3.cellclass'),
        Channel.value('RIRA_Immune.cellclass'),
        Channel.value('RIRA_TNK_v2.cellclass:TNK,RIRA_Myeloid_v3.cellclass:Myeloid')
    )
}
