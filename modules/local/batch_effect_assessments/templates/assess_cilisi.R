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
cells_csv <- Sys.getenv('CILISI_CELLS_CSV', unset = NA_character_)

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
    if (!is.na(cells_csv) && nzchar(cells_csv)) {
        write.csv(
            data.frame(cell_barcode = character(0), cilisi_value = numeric(0),
                       celltype = character(0), batch = character(0),
                       stringsAsFactors = FALSE),
            cells_csv, row.names = FALSE
        )
    }
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
    if (!is.na(cells_csv) && nzchar(cells_csv)) {
        write.csv(
            data.frame(cell_barcode = character(0), cilisi_value = numeric(0),
                       celltype = character(0), batch = character(0),
                       stringsAsFactors = FALSE),
            cells_csv, row.names = FALSE
        )
    }
    quit(save = 'no', status = 0)
}

obj <- readRDS(rds_path)
batch_col <- prep$batch_column
emb <- Embeddings(obj, reduction = reduction)
md <- obj[[]]

cilisi_vals <- NA_real_
msg <- ''
status <- 'ok'

if (requireNamespace('scIntegrationMetrics', quietly = TRUE)) {
    cilisi_vals <- tryCatch(
        run_cilisi(emb, md, batch_col, celltype_col),
        error = function(e) e
    )
    if (inherits(cilisi_vals, 'error')) {
        status <- 'na'
        msg <- conditionMessage(cilisi_vals)
        cilisi_vals <- NA_real_
    } else if (length(cilisi_vals) == 0) {
        status <- 'na'
        msg <- 'CiLISI: no cell-type groups passed min cell/batch filters'
    }
} else {
    status <- 'na'
    msg <- 'scIntegrationMetrics not available'
}

# Write per-cell CSV for downstream histogram visualization
if (!is.na(cells_csv) && nzchar(cells_csv)) {
    if (length(cilisi_vals) > 0 && !all(is.na(cilisi_vals))) {
        cell_barcodes <- if (!is.null(names(cilisi_vals))) names(cilisi_vals) else rownames(md)
        cell_df <- data.frame(
            cell_barcode = cell_barcodes,
            cilisi_value = as.numeric(cilisi_vals),
            celltype = as.character(md[cell_barcodes, celltype_col]),
            batch = as.character(md[cell_barcodes, batch_col]),
            stringsAsFactors = FALSE
        )
        write.csv(cell_df, cells_csv, row.names = FALSE)
    } else {
        write.csv(
            data.frame(cell_barcode = character(0), cilisi_value = numeric(0),
                       celltype = character(0), batch = character(0),
                       stringsAsFactors = FALSE),
            cells_csv, row.names = FALSE
        )
    }
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
