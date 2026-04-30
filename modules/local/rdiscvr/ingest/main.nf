/*
 * Process: INGEST
 *
 * Downloads a Seurat object from either:
 *   1. A public URL (meta.url) — uses download.file() + readRDS(), no auth needed
 *   2. LabKey/Prime-seq (meta.output_file_id) — uses Rdiscvr::DownloadOutputFile()
 *      with .netrc authentication
 *
 * The mode is auto-detected: if meta.url is present and non-empty, URL mode is used.
 * Otherwise, the legacy LabKey mode is used (requires labkey_base_url, labkey_folder, .netrc).
 */

process INGEST {
    tag 'ingest'
    label 'process_ingest'

    container 'ghcr.io/bimberlabinternal/rdiscvr:latest'

    publishDir "${params.outdir}/ingest", mode: 'copy'

    input:
    val(meta)

    output:
    tuple val(meta), path("${meta.id}.rds"), emit: rds
    tuple val(meta), path("${meta.id}_metadata.csv"), emit: metadata

    script:
    """
    #!/usr/bin/env Rscript
    options(warn = 2)

    suppressPackageStartupMessages({
        library(Seurat)
    })

    sample_id      <- "${meta.id}"
    species        <- "${meta.species}"
    url            <- "${meta.url ?: ''}"
    output_file_id <- "${meta.output_file_id ?: ''}"
    labkey_base    <- Sys.getenv("LABKEY_BASE_URL", unset = "${params.labkey_base_url}")
    labkey_folder  <- Sys.getenv("LABKEY_FOLDER", unset = "${params.labkey_folder}")

    message("[INGEST] Processing sample: ", sample_id)
    message("[INGEST] species          : ", species)

    out_path <- paste0(sample_id, ".rds")

    # --- URL mode: download from a public URL ---
    if (nzchar(url)) {
        message("[INGEST] Download mode    : URL")
        message("[INGEST] URL              : ", url)

        download.file(url = url, destfile = out_path, mode = "wb",
                      timeout = 600)
        if (!file.exists(out_path) || is.na(file.info(out_path)[["size"]]) || file.info(out_path)[["size"]] == 0) {
            stop("Download failed or produced empty file for sample: ", sample_id)
        }
        seurat_obj <- readRDS(out_path)

        if (!inherits(seurat_obj, "Seurat")) {
            stop("Downloaded object is not a Seurat instance for sample: ", sample_id)
        }

        seurat_obj[["sample_id"]] <- sample_id
        seurat_obj[["species"]] <- species
        seurat_obj[["source_url"]] <- url

        saveRDS(seurat_obj, file = out_path)
        metadata_path <- paste0(sample_id, "_metadata.csv")
        metadata_df <- seurat_obj@meta.data
        metadata_df\$sample_id <- sample_id
        metadata_df\$species <- species
        metadata_df\$source_url <- url
        utils::write.csv(metadata_df, file = metadata_path, row.names = TRUE)

        message("[INGEST] Cells loaded: ", ncol(seurat_obj))
        message("[INGEST] Genes loaded: ", nrow(seurat_obj))
        message("[INGEST] Saved Seurat object to: ", out_path)
        message("[INGEST] Saved metadata table to: ", metadata_path)

    # --- LabKey mode: download via Rdiscvr with .netrc auth ---
    } else if (nzchar(output_file_id)) {
        suppressPackageStartupMessages({
            library(Rdiscvr)
        })

        message("[INGEST] Download mode    : LabKey")
        message("[INGEST] output_file_id   : ", output_file_id)

        netrc_path <- Sys.getenv("LABKEY_NETRC_FILE",
                         unset = file.path(Sys.getenv("HOME", unset = "/root"), ".netrc"))

        if (!nzchar(labkey_base) || !nzchar(labkey_folder)) {
            stop("Both LABKEY_BASE_URL and LABKEY_FOLDER must be provided for LabKey downloads.")
        }
        if (!file.exists(netrc_path)) {
            stop("Expected LabKey credentials at: ", netrc_path)
        }

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
        metadata_path <- paste0(sample_id, "_metadata.csv")
        metadata_df <- seurat_obj@meta.data
        metadata_df\$sample_id <- sample_id
        metadata_df\$species <- species
        metadata_df\$output_file_id <- output_file_id
        utils::write.csv(metadata_df, file = metadata_path, row.names = TRUE)

        message("[INGEST] Cells loaded: ", ncol(seurat_obj))
        message("[INGEST] Genes loaded: ", nrow(seurat_obj))
        message("[INGEST] Saved Seurat object to: ", out_path)
        message("[INGEST] Saved metadata table to: ", metadata_path)

    } else {
        stop("Neither 'url' nor 'output_file_id' found in sample metadata for: ", sample_id)
    }
    """

    stub:
    """
    touch "${meta.id}.rds"
    touch "${meta.id}_metadata.csv"
    """
}
