/*
 * Process: EXPORT_COUNTS
 *
 * Extracts raw counts and cell metadata from a Seurat object into a 10x-like
 * matrix directory. The output is consumed by the Python harmonization step.
 */

process EXPORT_COUNTS {
    tag "${meta.id}"
    label 'process_export'

    container 'ghcr.io/bimberlabinternal/cellmembrane:latest'

    publishDir "${params.outdir}/counts/${meta.id}", mode: 'copy'

    input:
    tuple val(meta), path(rds)

    output:
    tuple val(meta), path("${meta.id}_counts"), emit: counts_dir

    stub:
    """
    mkdir -p "${meta.id}_counts"
    touch "${meta.id}_counts/matrix.mtx"
    touch "${meta.id}_counts/features.tsv"
    touch "${meta.id}_counts/barcodes.tsv"
    touch "${meta.id}_counts/obs_meta.csv"
    """

    script:
    """
    #!/usr/bin/env Rscript
    options(warn = 2)

    suppressPackageStartupMessages({
        library(Seurat)
        library(Matrix)
    })

    sample_id      <- "${meta.id}"
    sample_species <- "${meta.species}"
    output_file_id <- "${meta.output_file_id}"
    assay_name     <- "${params.export_assay}"
    out_dir        <- paste0(sample_id, "_counts")

    message("[EXPORT_COUNTS] Processing sample: ", sample_id)

    seurat_obj <- readRDS("${rds}")

    if (!(assay_name %in% names(seurat_obj@assays))) {
        stop("Requested assay not found in Seurat object: ", assay_name)
    }

    counts <- Seurat::GetAssayData(seurat_obj, assay = assay_name, layer = "counts")
    counts <- methods::as(counts, "dgCMatrix")

    obs_meta <- seurat_obj[[]]
    obs_meta <- obs_meta[colnames(counts), , drop = FALSE]
    obs_meta\$sample_id <- sample_id
    obs_meta\$species <- sample_species
    obs_meta\$output_file_id <- output_file_id
    obs_meta\$barcode <- colnames(counts)

    dir.create(out_dir, showWarnings = FALSE)
    Matrix::writeMM(counts, file = file.path(out_dir, "matrix.mtx"))
    write.table(rownames(counts), file = file.path(out_dir, "features.tsv"), sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)
    write.table(colnames(counts), file = file.path(out_dir, "barcodes.tsv"), sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)
    utils::write.csv(obs_meta, file = file.path(out_dir, "obs_meta.csv"), row.names = TRUE)

    message("[EXPORT_COUNTS] Cells exported: ", ncol(counts))
    message("[EXPORT_COUNTS] Genes exported: ", nrow(counts))
    message("[EXPORT_COUNTS] Output directory: ", out_dir)
    """
}
