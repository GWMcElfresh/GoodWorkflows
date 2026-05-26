/*
 * Process: EXTRACT_TCR_SEQUENCES
 *
 * Reads an ingested Seurat RDS and extracts TRA/TRB (CDR3) sequences into a
 * long-format CSV suitable for ESM-2 embedding.
 *
 * Expected Seurat meta.data columns:
 *   - cDNA_ID
 *   - SubjectId
 *   - TRA, TRB (comma-separated sequences allowed)
 * Optional (for Rdiscvr-style conflicting V/J dropping):
 *   - TRA_V, TRA_J
 *   - TRB_V, TRB_J
 */

process EXTRACT_TCR_SEQUENCES {
    tag 'extract-tcr-sequences'
    label 'process_tabulate'

    container 'ghcr.io/bimberlabinternal/rdiscvr:latest'

    input:
    tuple val(meta), path(rds)

    output:
    tuple val(meta), path("${meta.id}_tcr_sequences.csv"), emit: sequences_csv

    script:
    template 'extract_tcr_sequences.R'

    stub:
    """
    printf 'cDNA_ID,SubjectId,barcode,chain,sequence,sequence_index,v_gene,j_gene\\n' > "${meta.id}_tcr_sequences.csv"
    """
}

