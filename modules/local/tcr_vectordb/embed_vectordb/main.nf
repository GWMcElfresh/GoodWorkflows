/*
 * Process: EMBED_TCR_VECTORDATABASE
 *
 * Reads the extracted long-format TRA/TRB sequences CSV, runs ESM-2
 * embeddings, and writes parquet vector databases plus a persisted nearest-
 * neighbor index for each cDNA_ID.
 *
 * Outputs are published under: ${params.outdir}/tcr_vectordbs/
 */

process EMBED_TCR_VECTORDATABASE {
    tag 'embed-tcr-vectordb'
    label 'process_gpu'

    container { params.milton_container }

    publishDir "${params.outdir}/tcr_vectordbs", mode: 'copy'

    input:
    tuple val(meta), path(sequences_csv)

    output:
    path('vectordb_out'), emit: vectordb_dir

    script:
    template 'embed_esm2_vectordb.py'

    stub:
    """
    mkdir -p vectordb_out
    # Stub-run: assume one cDNA_ID per sample and use sample_id for filenames.
    touch "vectordb_out/${meta.id}_single.parquet"
    touch "vectordb_out/${meta.id}_paired.parquet"
    touch "vectordb_out/${meta.id}_single_index.joblib"
    touch "vectordb_out/${meta.id}_paired_index.joblib"
    """
}

