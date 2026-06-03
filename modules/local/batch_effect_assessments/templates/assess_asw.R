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
cells_csv <- Sys.getenv('ASW_CELLS_CSV', unset = NA_character_)

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
    if (!is.na(cells_csv) && nzchar(cells_csv)) {
        write.csv(
            data.frame(cell_barcode = character(0), batch_asw = numeric(0),
                       celltype_asw = numeric(0), batch = character(0),
                       stringsAsFactors = FALSE),
            cells_csv, row.names = FALSE
        )
    }
    quit(save = 'no', status = 0)
}

obj <- readRDS(rds_path)
batch_col <- prep$batch_column
celltype_col <- prep$celltype_column
emb <- Embeddings(obj, reduction = reduction)
md <- obj[[]]
rm(obj)
invisible(gc())

batch_asw <- NA_real_
celltype_asw <- NA_real_
cell_barcodes <- NULL
msg <- c()
status <- 'ok'

n_cells <- nrow(emb)

# Downsample if silhouette would O(n^2) with >50K cells (avoids R .C long-vectors limit)
if (n_cells > 50000 && (run_batch || run_celltype)) {
    ds_label <- if (run_batch) batch_col else celltype_col
    ds <- stratified_downsample(emb, md, ds_label)
    emb <- ds$emb
    md <- ds$md
    msg <- c(msg, sprintf(
        'downsampled from %d to %d cells (stratified by %s)',
        n_cells, nrow(emb), ds_label
    ))
}

if (requireNamespace('scIntegrationMetrics', quietly = TRUE)) {
    if (run_batch) {
        batch_vals <- tryCatch(
            run_batch_asw(emb, md, batch_col),
            error = function(e) e
        )
        if (inherits(batch_vals, 'error')) {
            status <- 'na'
            msg <- c(msg, conditionMessage(batch_vals))
        } else {
            batch_asw <- mean(batch_vals, na.rm = TRUE)
            cell_barcodes <- names(batch_vals)
        }
    }
    if (run_celltype && !is.null(celltype_col) && !is.na(celltype_col) && nzchar(celltype_col)) {
        celltype_vals <- tryCatch(
            run_celltype_asw(emb, md, celltype_col),
            error = function(e) e
        )
        if (inherits(celltype_vals, 'error')) {
            status <- 'na'
            msg <- c(msg, conditionMessage(celltype_vals))
        } else {
            celltype_asw <- mean(celltype_vals, na.rm = TRUE)
            if (is.null(cell_barcodes)) cell_barcodes <- names(celltype_vals)
        }
    } else if (run_celltype) {
        msg <- c(msg, 'celltype_ASW skipped (no inferable celltype column)')
    }
} else {
    status <- 'na'
    msg <- c(msg, 'scIntegrationMetrics not available')
}

# Write per-cell CSV for downstream histogram visualization
# Use rownames(emb) for cell barcodes since as.numeric strips scIntegrationMetrics row names.
if (!is.na(cells_csv) && nzchar(cells_csv)) {
    has_batch <- (exists('batch_vals') && !inherits(batch_vals, 'error') && length(batch_vals) > 0)
    has_celltype <- (exists('celltype_vals') && !inherits(celltype_vals, 'error') && length(celltype_vals) > 0)
    if (has_batch || has_celltype) {
        n_vals <- if (has_batch) length(batch_vals) else length(celltype_vals)
        cell_df <- data.frame(
            cell_barcode = rownames(emb),
            batch_asw = if (has_batch) as.numeric(batch_vals) else NA_real_,
            celltype_asw = if (has_celltype) as.numeric(celltype_vals) else NA_real_,
            batch = as.character(md[[batch_col]]),
            stringsAsFactors = FALSE
        )
        if (!is.na(celltype_col) && nzchar(celltype_col)) {
            cell_df$celltype <- as.character(md[[celltype_col]])
        }
        write.csv(cell_df, cells_csv, row.names = FALSE)
    } else {
        write.csv(
            data.frame(cell_barcode = character(0), batch_asw = numeric(0),
                       celltype_asw = numeric(0), batch = character(0),
                       stringsAsFactors = FALSE),
            cells_csv, row.names = FALSE
        )
    }
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
