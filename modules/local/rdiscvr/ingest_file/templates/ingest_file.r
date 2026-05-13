#!/usr/bin/env Rscript
# Nextflow template: ingest_file.r
# INGEST_FILE — copy and validate a local Seurat RDS (or table/h5ad) into the pipeline.
#
# Nextflow substitutions:
#   ${meta.id}      – sample identifier
#   ${meta.species} – sample species label
#   ${meta.path}    – original filesystem path (for logging / suffix detection)
#   ${source_file}  – Nextflow-staged local path

options(warn = 2)

suppressPackageStartupMessages({
    library(Seurat)
})

sample_id      <- "${meta.id}"
species        <- "${meta.species}"
source_path    <- "${meta.path}"
staged_file    <- "${source_file}"

message("[INGEST_FILE] Processing sample: ", sample_id)
message("[INGEST_FILE] species          : ", species)
message("[INGEST_FILE] source_path      : ", source_path)
message("[INGEST_FILE] staged_file      : ", staged_file)

if (!file.exists(staged_file)) {
    stop("[INGEST_FILE] Staged file not found (Nextflow staging error): ", staged_file)
}

suffix <- tolower(tools::file_ext(source_path))
message("[INGEST_FILE] Detected suffix  : ", suffix)

out_path      <- paste0(sample_id, ".rds")
metadata_path <- paste0(sample_id, "_metadata.csv")

if (!suffix %in% c("rds", "rdata", "rda", "h5ad", "csv", "tsv", "txt")) {
    stop("Unsupported file extension '", suffix, "' for file: ", source_path)
}

if (suffix == "rds") {
    seurat_obj <- readRDS(staged_file)
} else if (suffix %in% c("csv", "tsv", "txt")) {
    message("[INGEST_FILE] Building Seurat object from a count matrix: ", source_path)
    counts <- data.table::fread(staged_file, data.table = FALSE)
    row.names(counts) <- counts[[1]]
    counts[[1]] <- NULL
    counts <- as.matrix(counts)
    seurat_obj <- CreateSeuratObject(
        counts = counts,
        project = sample_id,
        min.cells = 0,
        min.features = 0
    )
    message("[INGEST_FILE] Built Seurat object with ", ncol(seurat_obj),
            " cells and ", nrow(seurat_obj), " genes.")
} else if (suffix == "h5ad") {
    message("[INGEST_FILE] Converting h5ad to Seurat via reticulate...")
    if (!requireNamespace("anndata", quietly = TRUE)) {
        stop("Package 'anndata' is required for .h5ad file processing.")
    }
    ad <- anndata::read_h5ad(staged_file)
    seurat_obj <- CreateSeuratObject(
        counts = t(as.matrix(ad\$X)),
        project = sample_id,
        min.cells = 0,
        min.features = 0
    )
    message("[INGEST_FILE] Converted h5ad to Seurat: ", ncol(seurat_obj),
            " cells, ", nrow(seurat_obj), " genes.")
} else {
    file.copy(from = staged_file, to = out_path, overwrite = TRUE)
    seurat_obj <- readRDS(out_path)
}

if (!inherits(seurat_obj, "Seurat")) {
    stop("Loaded object is not a Seurat instance for sample: ", sample_id)
}

seurat_obj[["sample_id"]] <- sample_id
seurat_obj[["species"]] <- species
seurat_obj[["source_path"]] <- source_path

saveRDS(seurat_obj, file = out_path)
metadata_df <- seurat_obj@meta.data
metadata_df[["sample_id"]] <- sample_id
metadata_df[["species"]] <- species
metadata_df[["source_path"]] <- source_path
utils::write.csv(metadata_df, file = metadata_path, row.names = TRUE)

message("[INGEST_FILE] Cells loaded: ", ncol(seurat_obj))
message("[INGEST_FILE] Genes loaded: ", nrow(seurat_obj))
message("[INGEST_FILE] Saved Seurat object to: ", out_path)
message("[INGEST_FILE] Saved metadata table to: ", metadata_path)
