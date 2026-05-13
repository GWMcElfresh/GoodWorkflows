#!/usr/bin/env Rscript
# Nextflow template: merge_gex.r
# GEX_MERGE_COUNTS — merge per-sample 10x counts into a joint AnnData for mil-ton.
#
# Nextflow substitutions:
#   ${count_dirs}  — space-separated list of {sample_id}_counts/ directories

options(warn = 2)

suppressPackageStartupMessages({
    library(Seurat)
    library(anndata)
    library(Matrix)
    library(data.table)
})

message("[GEX_MERGE_COUNTS] Starting merge.")

# Count directories are staged by Nextflow as subdirectories of the work dir
count_dirs <- list.dirs(".", recursive = FALSE, full.names = TRUE)
count_dirs <- count_dirs[grepl("_counts\$", count_dirs)]
message("[GEX_MERGE_COUNTS] Found ", length(count_dirs), " count directories.")

read_one_count_dir <- function(dir) {
    sample_id <- sub("_counts\$", "", basename(dir))
    mtx  <- Matrix::readMM(file.path(dir, "matrix.mtx"))
    feat <- data.table::fread(file.path(dir, "features.tsv"), header = FALSE)\$V1
    barc <- data.table::fread(file.path(dir, "barcodes.tsv"), header = FALSE)\$V1
    meta <- data.table::fread(file.path(dir, "obs_meta.csv"), header = TRUE)

    rownames(mtx) <- feat
    colnames(mtx) <- barc

    # Annotate with sample_id if not already present
    if (!"sample_id" %in% names(meta)) {
        meta\$sample_id <- sample_id
    }
    meta\$barcode <- barc

    list(mtx = mtx, meta = meta, sample_id = sample_id)
}

parts <- lapply(count_dirs, read_one_count_dir)

# Merge counts
matrices <- lapply(parts, `[[`, "mtx")
all_genes <- unique(unlist(lapply(matrices, rownames)))
joint_mtx <- do.call(cbind, lapply(matrices, function(m) {
    missing_genes <- setdiff(all_genes, rownames(m))
    if (length(missing_genes) > 0) {
        pad <- Matrix(0, nrow = length(missing_genes), ncol = ncol(m), sparse = TRUE)
        rownames(pad) <- missing_genes
        m <- rbind(m, pad)
    }
    m[all_genes, , drop = FALSE]
}))

# Merge metadata
metas <- lapply(parts, `[[`, "meta")
joint_meta <- data.table::rbindlist(metas, fill = TRUE, use.names = TRUE)

# Ensure all character columns for h5py compatibility
for (col in names(joint_meta)) {
    if (!is.character(joint_meta[[col]])) {
        joint_meta[[col]] <- as.character(joint_meta[[col]])
    }
}

setorder(joint_meta, sample_id, barcode)

# Re-order columns to match matrix
joint_meta <- joint_meta[match(colnames(joint_mtx), barcode)]

stopifnot(ncol(joint_mtx) == nrow(joint_meta))

# Write AnnData
adata <- anndata::AnnData(
    X      = t(joint_mtx),   # cells x genes (dense or sparse)
    obs    = joint_meta,
    var    = data.frame(gene_id = all_genes, row.names = all_genes),
    obsm   = list(),
    layers = list(counts = t(joint_mtx))
)

anndata::write_h5ad(adata, "merged_gex.h5ad")

# Write cell metadata
data.table::fwrite(joint_meta, "cell_metadata.csv", showProgress = FALSE)

message("[GEX_MERGE_COUNTS] Merged: ", ncol(joint_mtx), " cells x ", nrow(joint_mtx), " genes.")
message("[GEX_MERGE_COUNTS] Written: merged_gex.h5ad + cell_metadata.csv")
