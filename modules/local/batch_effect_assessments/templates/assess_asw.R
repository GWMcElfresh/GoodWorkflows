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
run_batch <- method_enabled(methods, 'ASW')
run_celltype <- method_enabled(methods, 'CELLTYPE_ASW')

if (!run_batch && !run_celltype) {
    write.csv(
        data.frame(
            sample_id = prep$sample_id,
            reduction = reduction,
            metric = 'asw',
            status = 'skipped',
            message = 'ASW metrics not requested',
            stringsAsFactors = FALSE
        ),
        out_csv,
        row.names = FALSE
    )
    quit(save = 'no', status = 0)
}

obj <- readRDS(rds_path)
batch_col <- prep$batch_column
celltype_col <- prep$celltype_column
emb <- Embeddings(obj, reduction = reduction)
md <- obj[['meta.data']]

batch_asw <- NA_real_
celltype_asw <- NA_real_
msg <- c()
status <- 'ok'

if (requireNamespace('scIntegrationMetrics', quietly = TRUE)) {
    if (run_batch && exists('batch_ASW', where = asNamespace('scIntegrationMetrics'), inherits = FALSE)) {
        batch_asw <- scIntegrationMetrics::batch_ASW(emb, as.character(md[[batch_col]]))
    } else if (run_batch) {
        msg <- c(msg, 'batch_ASW not found in scIntegrationMetrics')
    }
    if (run_celltype && !is.null(celltype_col) && !is.na(celltype_col) &&
        exists('celltype_ASW', where = asNamespace('scIntegrationMetrics'), inherits = FALSE)) {
        celltype_asw <- scIntegrationMetrics::celltype_ASW(
            emb,
            as.character(md[[celltype_col]])
        )
    } else if (run_celltype) {
        msg <- c(msg, 'celltype_ASW skipped (missing column or function)')
    }
} else {
    status <- 'na'
    msg <- c(msg, 'scIntegrationMetrics not available')
}

write.csv(
    data.frame(
        sample_id = prep$sample_id,
        reduction = reduction,
        metric = 'asw',
        batch_asw = batch_asw,
        batch_mixing_score = if (is.na(batch_asw)) NA_real_ else 1 - batch_asw,
        celltype_asw = celltype_asw,
        celltype_mixing_score = if (is.na(celltype_asw)) NA_real_ else 1 - celltype_asw,
        status = status,
        message = paste(msg, collapse = '; '),
        stringsAsFactors = FALSE
    ),
    out_csv,
    row.names = FALSE
)
