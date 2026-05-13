/*
 * Process: EMBED_CLONES
 *
 * Embeds TCR CDR3 sequences using ESM-2 (facebook/esm2_t6_8M_UR50D, 320-dim).
 * Mean-pools last_hidden_state[:,1:-1,:] per sequence to produce a fixed-size
 * clone embedding vector. Deduplicates clones by TRA+TRB CDR3 combo to avoid
 * redundant computation.
 *
 * Accepts:
 *   - merged_tcr_metadata.csv from MERGE_TCR_METADATA
 *   - epitope_fasta: FASTA file of epitope sequences to embed alongside TCRs
 *
 * Produces:
 *   - clone_embeddings.parquet (clone_id, embedding_0..319)
 */

process EMBED_CLONES {
    tag 'embed-clones'
    label 'process_gpu'

    container { params.milton_tcr_container }

    publishDir "${params.outdir}/tcr_epitope", mode: 'copy'

    input:
    path tcr_metadata_csv
    path epitope_fasta

    output:
    path('clone_embeddings.parquet'), emit: clone_embeddings_umap
    path('clone_embeddings.parquet'), emit: clone_embeddings_pred

    script:
    template 'embed_esm2.py'

    stub:
    """
    touch clone_embeddings.parquet
    """
}