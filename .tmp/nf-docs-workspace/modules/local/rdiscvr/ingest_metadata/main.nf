/*
 * Process: INGEST_METADATA
 *
 * Downloads sample metadata only from prime-seq / LabKey using Rdiscvr's
 * DownloadMetadataForSeuratObject() and writes a normalized per-sample CSV
 * for downstream tabulation. Authentication is expected to come from a
 * read-only .netrc mount.
 */

process INGEST_METADATA {
    tag "${meta.id}"
    label 'process_ingest'

    container 'ghcr.io/bimberlabinternal/rdiscvr:latest'

    publishDir "${params.outdir}/ingest/${meta.id}", mode: 'copy'

    input:
    val(meta)

    output:
    tuple val(meta), path("${meta.id}_metadata.csv"), emit: metadata

    stub:
    """
    printf 'cDNA_ID\n' > "${meta.id}_metadata.csv"
    """

    script:
    """
    #!/usr/bin/env Rscript
    options(warn = 2)

    suppressWarnings(suppressPackageStartupMessages({
        library(Rdiscvr)
    }))

    sample_id      <- "${meta.id}"
    output_file_id <- as.integer("${meta.output_file_id}")
    species        <- "${meta.species}"
    labkey_base    <- Sys.getenv("LABKEY_BASE_URL", unset = "${params.labkey_base_url}")
    labkey_folder  <- Sys.getenv("LABKEY_FOLDER", unset = "${params.labkey_folder}")
    netrc_path     <- Sys.getenv("LABKEY_NETRC_FILE",
                         unset = file.path(Sys.getenv("HOME", unset = "/root"), ".netrc"))

    message("[INGEST_METADATA] Processing sample: ", sample_id)
    message("[INGEST_METADATA] output_file_id   : ", output_file_id)
    message("[INGEST_METADATA] species          : ", species)

    download_stem <- paste0(sample_id, "_metadata_download")
    metadata_path <- paste0(sample_id, "_metadata.csv")

    if (!nzchar(labkey_base) || !nzchar(labkey_folder)) {
        stop("Both LABKEY_BASE_URL and LABKEY_FOLDER must be provided.")
    }
    if (!file.exists(netrc_path)) {
        stop("Expected LabKey credentials at: ", netrc_path)
    }

    Rdiscvr::SetLabKeyDefaults(baseUrl = labkey_base, defaultFolder = labkey_folder)
    metadata_df <- Rdiscvr::DownloadMetadataForSeuratObject(
        outputFileId = output_file_id,
        outFile = download_stem,
        overwrite = TRUE,
        returnDataFrame = TRUE,
        deleteFile = TRUE,
        showProgressBar = FALSE
    )

    if (!is.data.frame(metadata_df)) {
        stop("Downloaded metadata is not a data.frame for sample: ", sample_id)
    }

    metadata_df <- as.data.frame(metadata_df, stringsAsFactors = FALSE)
    if (nrow(metadata_df) == 0) {
        stop("Downloaded metadata is empty for sample: ", sample_id)
    }
    if (!'cDNA_ID' %in% colnames(metadata_df)) {
        stop("Downloaded metadata is missing required cDNA_ID column for sample: ", sample_id)
    }

    if ('cellbarcode' %in% colnames(metadata_df) && !'barcode' %in% colnames(metadata_df)) {
        metadata_df\$barcode <- metadata_df[['cellbarcode']]
    }
    if ('RIRA_Immune_v2.cellclass' %in% colnames(metadata_df) &&
        !'RIRA_Immune.cellclass' %in% colnames(metadata_df)) {
        metadata_df[['RIRA_Immune.cellclass']] <- metadata_df[['RIRA_Immune_v2.cellclass']]
    }

    metadata_df\$sample_id <- sample_id
    metadata_df\$species <- species
    metadata_df\$output_file_id <- as.character(output_file_id)

    default_rownames <- identical(rownames(metadata_df), as.character(seq_len(nrow(metadata_df))))
    write_row_names <- !('barcode' %in% colnames(metadata_df)) && !default_rownames

    utils::write.csv(metadata_df, file = metadata_path, row.names = write_row_names)

    message("[INGEST_METADATA] Rows loaded: ", nrow(metadata_df))
    message("[INGEST_METADATA] Columns     : ", ncol(metadata_df))
    message("[INGEST_METADATA] Saved metadata table to: ", metadata_path)
    """
}