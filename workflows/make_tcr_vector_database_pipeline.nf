nextflow.enable.dsl = 2

include { INGEST_LABKEY } from '../modules/local/rdiscvr/ingest_labkey/main.nf'
include { INGEST_URL }    from '../modules/local/rdiscvr/ingest_url/main.nf'
include { INGEST_FILE }   from '../modules/local/rdiscvr/ingest_file/main.nf'

include { EXTRACT_TCR_SEQUENCES } from '../modules/local/tcr_vectordb/extract_tcr_sequences/main.nf'
include { EMBED_TCR_VECTORDATABASE } from '../modules/local/tcr_vectordb/embed_vectordb/main.nf'

/*
 * Samplesheet format for make_tcr_vector_database:
 *
 *   sample_id,output_file_id|url|path,species(optional)
 *
 * The pipeline expects the ingested Seurat object to contain:
 *   - cDNA_ID
 *   - SubjectId
 *   - TRA / TRB columns (comma-separated sequences are allowed)
 *   - optional: TRA_V / TRA_J / TRB_V / TRB_J for Rdiscvr-style
 *     conflicting V/J dropping before embedding
 */

def buildMakeTcrVectorDatabaseSamplesChannel(samplesheetPath) {
    Channel
        .fromPath(samplesheetPath, checkIfExists: true)
        .splitCsv(header: true, strip: true)
        .map { row ->
            if (!row.sample_id) {
                error "Samplesheet missing required value for column 'sample_id': ${row}"
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

            def meta = [ id: row.sample_id.toString() ]

            // Include species if present; needed by INGEST_FILE.
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

workflow MAKE_TCR_VECTOR_DATABASE_PIPELINE {
    take:
    samplesheet

    main:
    ch_samples = buildMakeTcrVectorDatabaseSamplesChannel(samplesheet)

    def ch_branched = ch_samples.branch { meta ->
        labkey: meta.mode == 'labkey'
        url:    meta.mode == 'url'
        file:   meta.mode == 'file'
    }

    // ── 1. Ingest Seurat RDS per sample ────────────────────────────────────
    def ch_ingested = INGEST_LABKEY(ch_branched.labkey).rds
        .mix(INGEST_URL(ch_branched.url).rds)
        .mix(INGEST_FILE(ch_branched.file.map { m -> tuple(m, file(m.path)) }).rds)

    // ── 2. Extract TRA/TRB sequences into a long table ────────────────────
    EXTRACT_TCR_SEQUENCES(ch_ingested)

    // ── 3. ESM-2 embed and write parquet/vector-index outputs ────────────
    EMBED_TCR_VECTORDATABASE(EXTRACT_TCR_SEQUENCES.out.sequences_csv)

    emit:
    vectordb = EMBED_TCR_VECTORDATABASE.out.vectordb_dir
}

