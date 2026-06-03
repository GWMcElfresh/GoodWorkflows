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
    md <- obj[[]]
    ilisi_vals <- tryCatch(
        run_ilisi(emb, md, batch_col),
        error = function(e) e
    )
    if (inherits(ilisi_vals, 'error')) {
        status <- 'na'
        msg <- conditionMessage(ilisi_vals)
        ilisi_vals <- NA_real_
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
