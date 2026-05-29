nextflow.enable.dsl = 2

include { INGEST_LABKEY } from '../modules/local/rdiscvr/ingest_labkey/main.nf'
include { INGEST_URL }    from '../modules/local/rdiscvr/ingest_url/main.nf'
include { INGEST_FILE }   from '../modules/local/rdiscvr/ingest_file/main.nf'

include { PREP_BATCH_ASSESSMENT }     from '../modules/local/batch_effect_assessments/prep/main.nf'
include { ASSESS_ILISI }              from '../modules/local/batch_effect_assessments/assess_ilisi/main.nf'
include { ASSESS_CILISI }             from '../modules/local/batch_effect_assessments/assess_cilisi/main.nf'
include { ASSESS_ASW }                from '../modules/local/batch_effect_assessments/assess_asw/main.nf'
include { ASSESS_KBET }               from '../modules/local/batch_effect_assessments/assess_kbet/main.nf'
include { COLLECT_BATCH_ASSESSMENT }  from '../modules/local/batch_effect_assessments/collect/main.nf'

/*
 * Samplesheet columns (in addition to tri-mode ingest columns):
 *   batch_column — meta.data column holding batch labels (required per row)
 *   integration_assessment_methods — comma-separated tokens (default LISI,CiLISI,ASW,CELLTYPE_ASW; kBET opt-in)
 */

def buildBatchEffectAssessmentsSamplesChannel(samplesheetPath) {
    Channel
        .fromPath(samplesheetPath, checkIfExists: true)
        .splitCsv(header: true, strip: true)
        .map { row ->
            if (!row.sample_id) {
                error "Samplesheet missing required value for column 'sample_id': ${row}"
            }
            if (!row.batch_column?.trim()) {
                error "Samplesheet missing required value for column 'batch_column': ${row}"
            }

            def hasOutputFileId = row.containsKey('output_file_id') && row.output_file_id?.trim()
            def hasUrl = row.containsKey('url') && row.url?.trim()
            def hasPath = row.containsKey('path') && row.path?.trim()

            def modeCount = ([hasOutputFileId, hasUrl, hasPath].count { it }) as int
            if (modeCount == 0) {
                error "Samplesheet row must have one of 'output_file_id', 'url', or 'path': ${row}"
            }
            if (modeCount > 1) {
                error "Samplesheet row must have exactly ONE of 'output_file_id', 'url', or 'path': ${row}"
            }

            def methods = row.containsKey('integration_assessment_methods') && row.integration_assessment_methods?.trim()
                ? row.integration_assessment_methods.toString().trim().replaceAll('^"|"$', '')
                : params.batch_assessment_default_methods.toString()

            def meta = [
                id: row.sample_id.toString(),
                batch_column: row.batch_column.toString().trim(),
                integration_assessment_methods: methods,
            ]

            if (row.containsKey('species') && row.species?.trim()) {
                meta.species = row.species.toString()
            }
            if (hasOutputFileId) {
                meta.output_file_id = row.output_file_id.toString()
                meta.mode = 'labkey'
            }
            if (hasUrl) {
                meta.url = row.url.toString()
                meta.mode = 'url'
            }
            if (hasPath) {
                meta.path = row.path.toString()
                meta.mode = 'file'
            }

            meta
        }
}

workflow BATCH_EFFECT_ASSESSMENTS_PIPELINE {
    take:
    samplesheet

    main:
    ch_samples = buildBatchEffectAssessmentsSamplesChannel(samplesheet)

    def batchTpl = "${projectDir}/modules/local/batch_effect_assessments/templates"
    def tpl_batch_utils = file("${batchTpl}/batch_metrics_utils.R")
    def tpl_prep = file("${batchTpl}/prep_batch_assessment.R")
    def tpl_ilisi = file("${batchTpl}/assess_ilisi.R")
    def tpl_cilisi = file("${batchTpl}/assess_cilisi.R")
    def tpl_asw = file("${batchTpl}/assess_asw.R")
    def tpl_kbet = file("${batchTpl}/assess_kbet.R")
    def tpl_collect = file("${batchTpl}/collect_batch_assessment.R")

    def ch_branched = ch_samples.branch { meta ->
        labkey: meta.mode == 'labkey'
        url:    meta.mode == 'url'
        file:   meta.mode == 'file'
    }

    def ch_ingested = INGEST_LABKEY(ch_branched.labkey).rds
        .mix(INGEST_URL(ch_branched.url).rds)
        .mix(INGEST_FILE(ch_branched.file.map { m -> tuple(m, file(m.path)) }).rds)

    PREP_BATCH_ASSESSMENT(
        ch_ingested.map { meta, rds -> tuple(meta, rds, tpl_batch_utils, tpl_prep) }
    )

    def ch_prep_by_id = PREP_BATCH_ASSESSMENT.out.prep
        .map { meta, prep_json -> tuple(meta.id, meta, prep_json) }

    def ch_rds_by_id = ch_ingested.map { meta, rds -> tuple(meta.id, rds) }

    def ch_per_reduction = ch_prep_by_id
        .join(ch_rds_by_id)
        .flatMap { sample_id, meta, prep_json, rds ->
            def prep = new groovy.json.JsonSlurper().parseText(prep_json.text)
            prep.reductions.collect { red ->
                tuple(meta, rds, prep_json, red.toString())
            }
        }

    ASSESS_ILISI(ch_per_reduction.map { meta, rds, prep_json, red ->
        tuple(meta, rds, prep_json, red, tpl_batch_utils, tpl_ilisi)
    })
    ASSESS_CILISI(ch_per_reduction.map { meta, rds, prep_json, red ->
        tuple(meta, rds, prep_json, red, tpl_batch_utils, tpl_cilisi)
    })
    ASSESS_ASW(ch_per_reduction.map { meta, rds, prep_json, red ->
        tuple(meta, rds, prep_json, red, tpl_batch_utils, tpl_asw)
    })
    ASSESS_KBET(ch_per_reduction.map { meta, rds, prep_json, red ->
        tuple(meta, rds, prep_json, red, tpl_batch_utils, tpl_kbet)
    })

    def ch_key = ch_per_reduction
        .map { meta, rds, prep_json, reduction -> tuple("${meta.id}::${reduction}", meta, prep_json) }

    def ch_ilisi = ASSESS_ILISI.out.metrics
        .map { meta, reduction, csv -> tuple("${meta.id}::${reduction}", csv) }
    def ch_cilisi = ASSESS_CILISI.out.metrics
        .map { meta, reduction, csv -> tuple("${meta.id}::${reduction}", csv) }
    def ch_asw = ASSESS_ASW.out.metrics
        .map { meta, reduction, csv -> tuple("${meta.id}::${reduction}", csv) }
    def ch_kbet = ASSESS_KBET.out.metrics
        .map { meta, reduction, csv -> tuple("${meta.id}::${reduction}", csv) }

    def ch_collect_in = ch_key
        .join(ch_ilisi)
        .join(ch_cilisi)
        .join(ch_asw)
        .join(ch_kbet)
        .map { key, meta, prep_json, ilisi, cilisi, asw, kbet ->
            tuple(meta, prep_json, ilisi, cilisi, asw, kbet, tpl_collect)
        }

    COLLECT_BATCH_ASSESSMENT(ch_collect_in)

    emit:
    prep        = PREP_BATCH_ASSESSMENT.out.prep
    summaries   = COLLECT_BATCH_ASSESSMENT.out.summary
    run_summary = COLLECT_BATCH_ASSESSMENT.out.summary.collectFile(
        name: 'run_summary.csv',
        storeDir: "${params.outdir}/batch_effect_assessments",
        sort: true,
        keepHeader: true
    )
    ingested    = ch_ingested
}
