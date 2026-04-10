/*
 * Process: INGEST
 *
 * Downloads a Seurat object from prime-seq / LabKey using Rdiscvr's
 * DownloadOutputFile() and writes a sample-local RDS artifact for downstream
 * export. Authentication is expected to come from a read-only .netrc mount.
 */

process INGEST {
    tag "${meta.id}"
    label 'process_ingest'

    container 'ghcr.io/bimberlabinternal/rdiscvr:latest'

    publishDir "${params.outdir}/ingest/${meta.id}", mode: 'copy'

    input:
    tuple val(meta)

    output:
    tuple val(meta), path("${meta.id}.rds"), emit: rds

    stub:
    """
    touch "${meta.id}.rds"
    """

    script:
    """
    #!/usr/bin/env Rscript
    options(warn = 2)

    suppressPackageStartupMessages({
        library(Rdiscvr)
        library(Seurat)
    })

    sample_id      <- "${meta.id}"
    output_file_id <- as.integer("${meta.output_file_id}")
    species        <- "${meta.species}"
    labkey_base    <- Sys.getenv("LABKEY_BASE_URL", unset = "${params.labkey_base_url}")
    labkey_folder  <- Sys.getenv("LABKEY_FOLDER", unset = "${params.labkey_folder}")
    netrc_path     <- file.path(Sys.getenv("HOME", unset = "/tmp"), ".netrc")

    message("[INGEST] Processing sample: ", sample_id)
    message("[INGEST] output_file_id   : ", output_file_id)
    message("[INGEST] species          : ", species)

    out_path <- paste0(sample_id, ".rds")
    if (!nzchar(labkey_base) || !nzchar(labkey_folder)) {
        stop("Both LABKEY_BASE_URL and LABKEY_FOLDER must be provided.")
    }
    if (!file.exists(netrc_path)) {
        stop("Expected LabKey credentials at: ", netrc_path)
    }

    Rdiscvr::SetLabKeyDefaults(baseUrl = labkey_base, defaultFolder = labkey_folder)
    Rdiscvr::DownloadOutputFile(
        outputFileId = output_file_id,
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
    seurat_obj[["output_file_id"]] <- as.character(output_file_id)

    saveRDS(seurat_obj, file = out_path)
    message("[INGEST] Cells loaded: ", ncol(seurat_obj))
    message("[INGEST] Genes loaded: ", nrow(seurat_obj))
    message("[INGEST] Saved Seurat object to: ", out_path)
    """
}
