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
if (!method_enabled(methods, 'LISI')) {
    write.csv(
        data.frame(
            sample_id = prep$sample_id,
            reduction = reduction,
            metric = 'ilisi',
            status = 'skipped',
            message = 'LISI not requested',
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

ilisi_vals <- NA_real_
msg <- ''
status <- 'ok'

if (requireNamespace('scIntegrationMetrics', quietly = TRUE)) {
    # Package API: compute iLISI on embedding matrix + batch labels.
    md <- obj[['meta.data']]
    batches <- as.character(md[[batch_col]])
    if (exists('compute_iLISI', where = asNamespace('scIntegrationMetrics'), inherits = FALSE)) {
        ilisi_vals <- scIntegrationMetrics::compute_iLISI(emb, batches)
    } else if (exists('LISI', where = asNamespace('scIntegrationMetrics'), inherits = FALSE)) {
        ilisi_vals <- scIntegrationMetrics::LISI(emb, batches)
    } else {
        status <- 'na'
        msg <- 'scIntegrationMetrics installed but iLISI entrypoint not found'
    }
} else {
    status <- 'na'
    msg <- 'scIntegrationMetrics not available'
}

summary_row <- data.frame(
    sample_id = prep$sample_id,
    reduction = reduction,
    metric = 'ilisi',
    n_batches = prep$n_batches,
    ilisi_median = if (all(is.na(ilisi_vals))) NA_real_ else median(ilisi_vals, na.rm = TRUE),
    ilisi_mean = if (all(is.na(ilisi_vals))) NA_real_ else mean(ilisi_vals, na.rm = TRUE),
    status = status,
    message = msg,
    stringsAsFactors = FALSE
)
write.csv(summary_row, out_csv, row.names = FALSE)
