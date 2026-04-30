/*
 * Process: INGEST_URL
 *
 * Downloads a data file from a public URL (meta.url) and infers the file type
 * from the URL suffix. Supports:
 *   .rds  — Seurat RDS object (readRDS)
 *   .csv  — CSV/TSV table via data.table::fread (auto-detects delimiter)
 *   .tsv  — Same as CSV path
 *   .txt  — Same as CSV path (tab-delimited assumed unless comma-heavy)
 *
 * Falls back to readRDS() for unknown suffixes and catches errors gracefully.
 * Uses the rdiscvr container image for data.table dependency.
 * No LabKey, .netrc, or Rdiscvr library dependencies.
 *
 * This is the URL-only counterpart to INGEST (which handles LabKey output_file_id
 * fetches with .netrc auth). Use INGEST_URL when all samples in the samplesheet
 * have a 'url' column and no 'output_file_id' is needed.
 */

process INGEST_URL {
    tag 'ingest_url'
    label 'process_ingest_url'

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
        library(data.table)
    })

    sample_id <- "${meta.id}"
    species   <- "${meta.species}"
    url       <- "${meta.url ?: ''}"

    message("[INGEST_URL] Processing sample: ", sample_id)
    message("[INGEST_URL] species          : ", species)
    message("[INGEST_URL] url              : ", url)

    if (!nzchar(url)) {
        stop("INGEST_URL requires a non-empty 'url' in sample metadata for: ", sample_id)
    }

    out_path    <- paste0(sample_id, ".rds")
    meta_path   <- paste0(sample_id, "_metadata.csv")
    dl_tmp      <- paste0(sample_id, "_dl_tmp")

    # Determine file type from URL suffix
    url_lower <- tolower(url)
    suffix <- if (grepl("\\\\.rds\\$", url_lower, ignore.case = TRUE)) {
        "rds"
    } else if (grepl("\\\\.csv\\$", url_lower, ignore.case = TRUE)) {
        "csv"
    } else if (grepl("\\\\.tsv\\$", url_lower, ignore.case = TRUE)) {
        "tsv"
    } else if (grepl("\\\\.txt\\$", url_lower, ignore.case = TRUE)) {
        "txt"
    } else if (grepl("\\\\.h5ad\\$", url_lower, ignore.case = TRUE)) {
        "h5ad"
    } else {
        "unknown"
    }

    message("[INGEST_URL] Detected suffix  : ", suffix)

    # Download the file
    download.file(url = url, destfile = dl_tmp, mode = "wb",
                  timeout = 600)
    if (!file.exists(dl_tmp) || is.na(file.info(dl_tmp)[["size"]]) ||
        file.info(dl_tmp)[["size"]] == 0) {
        stop("Download failed or produced empty file for sample: ", sample_id)
    }

    msg_prefix <- "[INGEST_URL]"
    if (suffix %in% c("rds")) {
        # RDS file: direct Seurat read
        message(msg_prefix, " Loading RDS via readRDS...")
        seurat_obj <- readRDS(dl_tmp)
        if (!inherits(seurat_obj, "Seurat")) {
            stop("RDS file does not contain a Seurat object for sample: ", sample_id)
        }

    } else if (suffix %in% c("csv", "tsv", "txt")) {
        # Delimited table: auto-detect via data.table::fread
        message(msg_prefix, " Loading table via data.table::fread...")
        tbl <- data.table::fread(dl_tmp, data.table = FALSE)
        message(msg_prefix, " Table rows: ", nrow(tbl), ", cols: ", ncol(tbl))

        # Attempt to convert to a minimal Seurat object.
        # If the table looks like a counts matrix (first column = gene names,
        # numeric data elsewhere), try building from counts.
        # Otherwise, store the table in @meta.data and create a dummy assay.
        first_col <- tbl[[1]]
        numeric_cols <- vapply(tbl[, -1, drop = FALSE], is.numeric, logical(1))

        if (all(numeric_cols) && is.character(first_col) &&
            length(unique(first_col)) == length(first_col)) {
            # Looks like genes × cells matrix
            message(msg_prefix, " Table looks like a counts matrix — building Seurat from matrix")
            gene_names <- as.character(first_col)
            mat <- as.matrix(tbl[, -1, drop = FALSE])
            rownames(mat) <- gene_names
            colnames(mat) <- paste0(sample_id, "_", seq_len(ncol(mat)))
            seurat_obj <- CreateSeuratObject(counts = Matrix::Matrix(mat, sparse = TRUE),
                                              project = sample_id)
        } else {
            # Generic table: store as metadata with a dummy count
            message(msg_prefix, " Table stored as metadata (not a counts matrix)")
            dummy_mat <- Matrix::Matrix(
                matrix(0, nrow = 1, ncol = 1,
                       dimnames = list("PLACEHOLDER", paste0(sample_id, "_1"))),
                sparse = TRUE
            )
            seurat_obj <- CreateSeuratObject(counts = dummy_mat, project = sample_id)
            seurat_obj@meta.data <- cbind(seurat_obj@meta.data, tbl)
        }

    } else if (suffix == "h5ad") {
        # h5ad: try Seurat's ReadH5AD via SeuratDisk if available,
        # else error with guidance
        message(msg_prefix, " Loading h5ad file...")
        if (requireNamespace("SeuratDisk", quietly = TRUE)) {
            seurat_obj <- SeuratDisk::LoadH5Seurat(dl_tmp)
            if (!inherits(seurat_obj, "Seurat")) {
                stop("h5ad conversion did not produce a Seurat object for: ", sample_id)
            }
        } else {
            stop(
                "h5ad files require the SeuratDisk package. ",
                "Install with: remotes::install_github('mojaveazure/seurat-disk')"
            )
        }

    } else {
        # Unknown suffix: try readRDS as a fallback
        message(msg_prefix, " Unknown suffix '", suffix, "' — attempting readRDS as fallback...")
        tryCatch({
            seurat_obj <- readRDS(dl_tmp)
            if (!inherits(seurat_obj, "Seurat")) {
                stop("Fallback readRDS did not produce a Seurat object for: ", sample_id)
            }
        }, error = function(e) {
            stop(
                "Cannot determine file type for suffix '", suffix,
                "' and fallback readRDS failed. ",
                "Supported suffixes: .rds, .csv, .tsv, .txt, .h5ad"
            )
        })
    }

    # Attach sample metadata
    seurat_obj[["sample_id"]] <- sample_id
    seurat_obj[["species"]] <- species
    seurat_obj[["source_url"]] <- url

    saveRDS(seurat_obj, file = out_path)
    metadata_df <- seurat_obj@meta.data
    metadata_df\$sample_id <- sample_id
    metadata_df\$species <- species
    metadata_df\$source_url <- url
    utils::write.csv(metadata_df, file = meta_path, row.names = TRUE)

    file.remove(dl_tmp)
    message("[INGEST_URL] Cells loaded: ", ncol(seurat_obj))
    message("[INGEST_URL] Genes loaded: ", nrow(seurat_obj))
    message("[INGEST_URL] Saved Seurat object to: ", out_path)
    message("[INGEST_URL] Saved metadata table to: ", meta_path)
    """

    stub:
    """
    touch "${meta.id}.rds"
    touch "${meta.id}_metadata.csv"
    """
}