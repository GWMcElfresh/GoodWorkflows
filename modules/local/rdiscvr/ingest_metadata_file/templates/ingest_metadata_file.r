#!/usr/bin/env Rscript
# Nextflow template: ingest_metadata_file.r
# INGEST_METADATA_FILE — read, validate, and annotate a metadata CSV file.
#
# Nextflow substitutions:
#   ${meta.id}              – sample identifier
#   ${meta.species}         – sample species label
#   ${meta.metadata_path}   – original filesystem path (for logging)
#   ${metadata_file}        – Nextflow-staged metadata CSV path

options(warn = 2)

suppressWarnings(suppressPackageStartupMessages({
    library(readr)
}))

sample_id      <- "${meta.id}"
species        <- "${meta.species}"
source_path    <- "${meta.metadata_path}"
staged_file    <- "${metadata_file}"

message("[INGEST_METADATA_FILE] Processing sample: ", sample_id)
message("[INGEST_METADATA_FILE] species          : ", species)
message("[INGEST_METADATA_FILE] source_path      : ", source_path)
message("[INGEST_METADATA_FILE] staged_file      : ", staged_file)

if (!file.exists(staged_file)) {
    stop("[INGEST_METADATA_FILE] Staged file not found (Nextflow staging error): ", staged_file)
}

# Read the metadata CSV — handle row.names=TRUE format (barcode in first unnamed col)
metadata_df <- read_csv(staged_file, show_col_types = FALSE)

# If CSV was written with row.names=TRUE, first col is barcodes named '...1'
if ('...1' %in% colnames(metadata_df)) {
    metadata_df <- dplyr::rename(metadata_df, barcode = `...1`)
}

# Ensure barcode column exists
if (!'barcode' %in% colnames(metadata_df) && 'cellbarcode' %in% colnames(metadata_df)) {
    metadata_df <- dplyr::rename(metadata_df, barcode = cellbarcode)
}

# Validate required columns
if (!'cDNA_ID' %in% colnames(metadata_df)) {
    stop("[INGEST_METADATA_FILE] Missing required 'cDNA_ID' column in metadata CSV: ", source_path)
}

# Add pipeline columns
metadata_df[["sample_id"]] <- sample_id
metadata_df[["species"]] <- species
metadata_df[["source_path"]] <- source_path

# Write output
out_path <- paste0(sample_id, "_metadata.csv")

# Write with barcodes as row names so TABULATE can read them consistently
write.csv(metadata_df, file = out_path, row.names = FALSE)

message("[INGEST_METADATA_FILE] Rows loaded: ", nrow(metadata_df))
message("[INGEST_METADATA_FILE] Columns     : ", ncol(metadata_df))
message("[INGEST_METADATA_FILE] Saved to    : ", out_path)
