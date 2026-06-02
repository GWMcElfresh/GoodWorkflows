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

prep <- fromJSON(prep_path)
methods <- prep$methods
if (!method_enabled(methods, 'CILISI')) {
    write.csv(
        data.frame(
            sample_id = prep$sample_id,
            reduction = reduction,
            metric = 'cilisi',
            status = 'skipped',
            message = 'CiLISI not requested',
            stringsAsFactors = FALSE
        ),
        out_csv,
        row.names = FALSE
    )
    quit(save = 'no', status = 0)
}

celltype_col <- prep$celltype_column
if (is.null(celltype_col) || is.na(celltype_col) || !nzchar(celltype_col)) {
    write.csv(
        data.frame(
            sample_id = prep$sample_id,
            reduction = reduction,
            metric = 'cilisi',
            status = 'skipped',
            message = 'No inferable celltype column',
            cilisi_median = NA_real_,
            stringsAsFactors = FALSE
        ),
        out_csv,
        row.names = FALSE
    )
    quit(save = 'no', status = 0)
}

obj <- readRDS(rds_path)
batch_col <- prep$batch_column
emb <- Embeddings(obj, reduction = reduction)
md <- obj[[]]
batches <- as.character(md[[batch_col]])
celltypes <- as.character(md[[celltype_col]])

cilisi_vals <- NA_real_
msg <- ''
status <- 'ok'

if (requireNamespace('scIntegrationMetrics', quietly = TRUE)) {
    if (exists('compute_cLISI', where = asNamespace('scIntegrationMetrics'), inherits = FALSE)) {
        cilisi_vals <- scIntegrationMetrics::compute_cLISI(emb, batches, celltypes)
    } else if (exists('cLISI', where = asNamespace('scIntegrationMetrics'), inherits = FALSE)) {
        cilisi_vals <- scIntegrationMetrics::cLISI(emb, batches, celltypes)
    } else {
        status <- 'na'
        msg <- 'scIntegrationMetrics installed but cLISI entrypoint not found'
    }
} else {
    status <- 'na'
    msg <- 'scIntegrationMetrics not available'
}

write.csv(
    data.frame(
        sample_id = prep$sample_id,
        reduction = reduction,
        metric = 'cilisi',
        celltype_column = celltype_col,
        cilisi_median = if (all(is.na(cilisi_vals))) NA_real_ else median(cilisi_vals, na.rm = TRUE),
        status = status,
        message = msg,
        stringsAsFactors = FALSE
    ),
    out_csv,
    row.names = FALSE
)
