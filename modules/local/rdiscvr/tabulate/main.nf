/*
 * Process: TABULATE
 *
 * Builds a wide, subject-level table from per-sample Seurat metadata CSV files.
 *
 * Standard RIRA cell-type columns (RIRA_Immune.cellclass, RIRA_TNK_v2.cellclass,
 * RIRA_Myeloid_v3.cellclass) are always processed when present.  Any additional
 * columns named in tabulate_celltype_cols are processed on top of those.
 *
 * tabulate_parent_col / tabulate_celltype_parent_map define optional hierarchy
 * filters: a child column is computed only over rows where the parent column
 * equals the mapped value (e.g. RIRA_TNK_v2.cellclass is computed only over
 * cells whose RIRA_Immune.cellclass == "TNK").
 */

process TABULATE {
    tag "subjectIdTable"
    label 'process_tabulate'

    container 'ghcr.io/bimberlabinternal/rdiscvr:latest'

    publishDir "${params.outdir}/tabulate", mode: 'copy'

    input:
    path(metadata_csvs)
    val(tabulate_id_cols)
    val(tabulate_celltype_cols)
    val(tabulate_parent_col)
    val(tabulate_celltype_parent_map)

    output:
    path('subjectIdTable.csv'), emit: subject_table

    script:
    template 'tabulate.r'

    stub:
    """
    printf 'cDNA_ID\n' > subjectIdTable.csv
    """
}