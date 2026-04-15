nextflow.enable.dsl = 2

include { GENERATE_SYNTHETIC_METADATA } from './helpers/synthetic_fixtures.nf'
include { TABULATE } from '../../modules/local/rdiscvr/tabulate/main.nf'

workflow {
    GENERATE_SYNTHETIC_METADATA()

    TABULATE(
        GENERATE_SYNTHETIC_METADATA.out.metadata,
        Channel.value('cDNA_ID,SubjectId,Vaccine,Timepoint,Tissue'),
        Channel.value('RIRA_Immune.cellclass,RIRA_TNK_v2.cellclass,RIRA_Myeloid_v3.cellclass'),
        Channel.value('RIRA_Immune.cellclass'),
        Channel.value('RIRA_TNK_v2.cellclass:TNK,RIRA_Myeloid_v3.cellclass:Myeloid')
    )
}
