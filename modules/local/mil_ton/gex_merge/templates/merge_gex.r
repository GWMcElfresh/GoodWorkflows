     1|     1|#!/usr/bin/env Rscript
     2|     2|# Nextflow template: merge_gex.r
     3|     3|# GEX_MERGE_COUNTS — merge per-sample 10x counts into a joint AnnData for mil-ton.
     4|     4|#
     5|     5|# Nextflow substitutions:
     6|     6|#   ${count_dirs}  — space-separated list of {sample_id}_counts/ directories
     7|     7|
     8|     8|options(warn = 2)
     9|     9|
    10|    10|suppressPackageStartupMessages({
    11|    11|    library(Seurat)
    12|    12|    library(anndata)
    13|    13|    library(Matrix)
    14|    14|    library(data.table)
    15|    15|})
    16|    16|
    17|    17|message("[GEX_MERGE_COUNTS] Starting merge.")
    18|    18|
    19|    19|# Count directories are staged by Nextflow as subdirectories of the work dir
    20|    20|count_dirs <- list.dirs(".", recursive = FALSE, full.names = TRUE)
    21|    21|count_dirs <- count_dirs[grepl("_counts$", count_dirs)]
    22|    22|message("[GEX_MERGE_COUNTS] Found ", length(count_dirs), " count directories.")
    23|    23|
    24|    24|read_one_count_dir <- function(dir) {
    25|    25|    sample_id <- sub("_counts\\$", "", basename(dir))
    26|    26|    mtx  <- Matrix::readMM(file.path(dir, "matrix.mtx"))
    27|    27|    feat <- data.table::fread(file.path(dir, "features.tsv"), header = FALSE)\$V1
    28|    28|    barc <- data.table::fread(file.path(dir, "barcodes.tsv"), header = FALSE)\$V1
    29|    29|    meta <- data.table::fread(file.path(dir, "obs_meta.csv"), header = TRUE)
    30|    30|
    31|    31|    rownames(mtx) <- feat
    32|    32|    colnames(mtx) <- barc
    33|    33|
    34|    34|    # Annotate with sample_id if not already present
    35|    35|    if (!"sample_id" %in% names(meta)) {
    36|    36|        meta$sample_id <- sample_id
    37|    37|    }
    38|    38|    meta$barcode <- barc
    39|    39|
    40|    40|    list(mtx = mtx, meta = meta, sample_id = sample_id)
    41|    41|}
    42|    42|
    43|    43|parts <- lapply(count_dirs, read_one_count_dir)
    44|    44|
    45|    45|# Merge counts
    46|    46|matrices <- lapply(parts, `[[`, "mtx")
    47|    47|all_genes <- unique(unlist(lapply(matrices, rownames)))
    48|    48|joint_mtx <- do.call(cbind, lapply(matrices, function(m) {
    49|    49|    missing_genes <- setdiff(all_genes, rownames(m))
    50|    50|    if (length(missing_genes) > 0) {
    51|    51|        pad <- Matrix(0, nrow = length(missing_genes), ncol = ncol(m), sparse = TRUE)
    52|    52|        rownames(pad) <- missing_genes
    53|    53|        m <- rbind(m, pad)
    54|    54|    }
    55|    55|    m[all_genes, , drop = FALSE]
    56|    56|}))
    57|    57|
    58|    58|# Merge metadata
    59|    59|metas <- lapply(parts, `[[`, "meta")
    60|    60|joint_meta <- data.table::rbindlist(metas, fill = TRUE, use.names = TRUE)
    61|    61|
    62|    62|# Ensure all character columns for h5py compatibility
    63|    63|for (col in names(joint_meta)) {
    64|    64|    if (!is.character(joint_meta[[col]])) {
    65|    65|        joint_meta[[col]] <- as.character(joint_meta[[col]])
    66|    66|    }
    67|    67|}
    68|    68|
    69|    69|setorder(joint_meta, sample_id, barcode)
    70|    70|
    71|    71|# Re-order columns to match matrix
    72|    72|joint_meta <- joint_meta[match(colnames(joint_mtx), barcode)]
    73|    73|
    74|    74|stopifnot(ncol(joint_mtx) == nrow(joint_meta))
    75|    75|
    76|    76|# Write AnnData
    77|    77|adata <- anndata::AnnData(
    78|    78|    X      = t(joint_mtx),   # cells x genes (dense or sparse)
    79|    79|    obs    = joint_meta,
    80|    80|    var    = data.frame(gene_id = all_genes, row.names = all_genes),
    81|    81|    obsm   = list(),
    82|    82|    layers = list(counts = t(joint_mtx))
    83|    83|)
    84|    84|
    85|    85|anndata::write_h5ad(adata, "merged_gex.h5ad")
    86|    86|
    87|    87|# Write cell metadata
    88|    88|data.table::fwrite(joint_meta, "cell_metadata.csv", showProgress = FALSE)
    89|    89|
    90|    90|message("[GEX_MERGE_COUNTS] Merged: ", ncol(joint_mtx), " cells x ", nrow(joint_mtx), " genes.")
    91|    91|message("[GEX_MERGE_COUNTS] Written: merged_gex.h5ad + cell_metadata.csv")
    92|    92|