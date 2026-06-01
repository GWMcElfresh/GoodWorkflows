#!/usr/bin/env Rscript
source('batch_metrics_utils.R')

suppressPackageStartupMessages({
    library(Seurat)
    library(jsonlite)
})

rds_path <- Sys.getenv('RDS_PATH')
prep_path <- Sys.getenv('PREP_JSON')
reduction <- Sys.getenv('REDUCTION')
out_csv <- Sys.getenv('OUT_CSV')
cells_per_batch <- as.integer(Sys.getenv('KBET_CELLS_PER_BATCH', unset = '1000'))

prep <- fromJSON(prep_path)
methods <- prep$methods
if (!method_enabled(methods, 'KBET')) {
    write.csv(
        data.frame(
            sample_id = prep$sample_id,
            reduction = reduction,
            metric = 'kbet',
            status = 'skipped',
            message = 'kBET not requested',
            stringsAsFactors = FALSE
        ),
        out_csv,
        row.names = FALSE
    )
    quit(save = 'no', status = 0)
}

obj <- readRDS(rds_path)
batch_col <- prep$batch_column
md <- obj[[]]
batches <- as.character(md[[batch_col]])

# Downsample to target cells per batch (stratified), then re-run PCA for kBET.
set.seed(42L)
cells_keep <- c()
for (b in unique(batches)) {
    idx <- which(batches == b)
    n_take <- min(length(idx), cells_per_batch)
    cells_keep <- c(cells_keep, sample(idx, n_take))
}
obj <- subset(obj, cells = colnames(obj)[cells_keep])
if ('pca' %in% names(obj@reductions)) {
    obj <- Seurat::RunPCA(obj, verbose = FALSE)
}
emb <- Embeddings(obj, reduction = if (reduction %in% names(obj@reductions)) reduction else 'pca')

rejection <- NA_real_
expected <- NA_real_
msg <- ''
status <- 'ok'

if (requireNamespace('kBET', quietly = TRUE)) {
    res <- tryCatch(
        kBET::kBET(emb, batch = as.character(md[[batch_col]]), plot = FALSE),
        error = function(e) e
    )
    if (inherits(res, 'error')) {
        status <- 'na'
        msg <- conditionMessage(res)
    } else {
        if (!is.null(res$summary$kBET.observed)) {
            rejection <- res$summary$kBET.observed
        }
        if (!is.null(res$summary$kBET.expected)) {
            expected <- res$summary$kBET.expected
        }
    }
} else {
    status <- 'na'
    msg <- 'kBET package not available'
}

acceptance <- if (is.na(rejection)) NA_real_ else 1 - rejection
write.csv(
    data.frame(
        sample_id = prep$sample_id,
        reduction = reduction,
        metric = 'kbet',
        n_cells_after_downsample = ncol(obj),
        kbet_rejection_rate = rejection,
        kbet_acceptance_rate = acceptance,
        kbet_expected_rejection_rate = expected,
        status = status,
        message = msg,
        stringsAsFactors = FALSE
    ),
    out_csv,
    row.names = FALSE
)
