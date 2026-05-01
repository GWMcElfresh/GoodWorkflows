#!/usr/bin/env Rscript
# Nextflow template: ingest_labkey.r
# INGEST_LABKEY — download a Seurat object from LabKey via Rdiscvr.
#
# Nextflow substitutions:
#   ${meta.id}              – sample identifier
#   ${meta.species}         – sample species label
#   ${meta.output_file_id}  – LabKey output file ID integer
#   ${params.labkey_base_url} – LabKey base URL (fallback; env LABKEY_BASE_URL takes priority)
#   ${params.labkey_folder}   – LabKey folder path (fallback; env LABKEY_FOLDER takes priority)

options(warn = 2)

suppressPackageStartupMessages({
    library(Seurat)
})

sample_id      <- "${meta.id}"
species        <- "${meta.species}"
output_file_id <- "${meta.output_file_id}"
labkey_base    <- Sys.getenv("LABKEY_BASE_URL", unset = "${params.labkey_base_url}")
labkey_folder  <- Sys.getenv("LABKEY_FOLDER", unset = "${params.labkey_folder}")
netrc_path     <- Sys.getenv("LABKEY_NETRC_FILE",
                     unset = file.path(Sys.getenv("HOME", unset = "/root"), ".netrc"))

message("[INGEST_LABKEY] Processing sample: ", sample_id)
message("[INGEST_LABKEY] output_file_id   : ", output_file_id)
message("[INGEST_LABKEY] species          : ", species)

out_path      <- paste0(sample_id, ".rds")
metadata_path <- paste0(sample_id, "_metadata.csv")

if (!nzchar(labkey_base) || !nzchar(labkey_folder)) {
    stop("Both LABKEY_BASE_URL and LABKEY_FOLDER must be provided for LabKey downloads.")
}
if (!file.exists(netrc_path)) {
    stop("Expected LabKey credentials at: ", netrc_path)
}

suppressPackageStartupMessages({
    library(Rdiscvr)
})

Rdiscvr::SetLabKeyDefaults(baseUrl = labkey_base, defaultFolder = labkey_folder)
Rdiscvr::DownloadOutputFile(
    outputFileId = as.integer(output_file_id),
    outFile = out_path,
    overwrite = TRUE,
    showProgressBar = FALSE
)

seurat_obj <- readRDS(out_path)
if (!inherits(seurat_obj, "Seurat")) {
    stop("Downloaded object is not a Seurat instance for sample: ", sample_id)
}

seurat_obj[["sample_id"]] <- sample_id
seurat_obj[["species"]] <- species
seurat_obj[["output_file_id"]] <- output_file_id

saveRDS(seurat_obj, file = out_path)
metadata_df <- seurat_obj@meta.data
metadata_df[["sample_id"]] <- sample_id
metadata_df[["species"]] <- species
metadata_df[["output_file_id"]] <- output_file_id
utils::write.csv(metadata_df, file = metadata_path, row.names = TRUE)

message("[INGEST_LABKEY] Cells loaded: ", ncol(seurat_obj))
message("[INGEST_LABKEY] Genes loaded: ", nrow(seurat_obj))
message("[INGEST_LABKEY] Saved Seurat object to: ", out_path)
message("[INGEST_LABKEY] Saved metadata table to: ", metadata_path)
