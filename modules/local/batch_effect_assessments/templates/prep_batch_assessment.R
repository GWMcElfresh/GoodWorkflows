#!/usr/bin/env Rscript
source('batch_metrics_utils.R')

suppressPackageStartupMessages({
    library(Seurat)
    library(jsonlite)
})

rds_path <- Sys.getenv('RDS_PATH', unset = NA_character_)
batch_col <- Sys.getenv('BATCH_COLUMN', unset = NA_character_)
methods_raw <- Sys.getenv('INTEGRATION_ASSESSMENT_METHODS', unset = 'LISI,CiLISI,ASW,CELLTYPE_ASW')
min_cells <- as.integer(Sys.getenv('MIN_CELLS_PER_BATCH', unset = '20'))
sample_id <- Sys.getenv('SAMPLE_ID', unset = 'sample')
out_json <- Sys.getenv('PREP_JSON', unset = 'prep.json')

if (!nzchar(rds_path) || !file.exists(rds_path)) stop('RDS_PATH missing or not found')
if (!nzchar(batch_col)) stop('BATCH_COLUMN missing')

methods <- parse_methods(methods_raw)
obj <- readRDS(rds_path)
obj <- normalize_immune_aliases(obj)

if (!(batch_col %in% colnames(obj[['meta.data']]))) {
    stop('Batch column not present in meta.data: ', batch_col)
}

if (min_cells_per_batch(obj, batch_col, min_cells) < min_cells) {
    stop('At least one batch has fewer than ', min_cells, ' cells')
}

reductions <- discover_reductions(obj)
if (length(reductions) == 0) stop('No dimensional reductions found on Seurat object')

celltype_col <- infer_celltype_column(obj)
prep <- list(
    sample_id = sample_id,
    batch_column = batch_col,
    celltype_column = if (is.na(celltype_col)) NA else celltype_col,
    methods = methods,
    reductions = reductions,
    n_cells = ncol(obj),
    n_batches = length(unique(as.character(obj[['meta.data']][[batch_col]])))
)

write(toJSON(prep, auto_unbox = TRUE, pretty = TRUE), out_json)
