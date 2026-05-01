#!/usr/bin/env Rscript
# Nextflow template: export_counts.r
# EXPORT_COUNTS — extract raw counts and cell metadata from a Seurat object.
#
# Nextflow substitutions:
#   ${meta.id}              – sample identifier
#   ${meta.species}         – sample species label
#   ${meta.output_file_id}  – LabKey output file ID (may be empty for URL/file modes)
#   ${params.export_assay}  – Seurat assay name to export (e.g. "RNA")
#   ${rds}                  – staged path to input Seurat RDS

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
