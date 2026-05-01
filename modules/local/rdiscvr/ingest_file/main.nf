/*
 * Process: INGEST_FILE
 *
 * Copies a Seurat object from a local filesystem path, then reads and validates it.
 *
 * This is the local-file counterpart to INGEST_LABKEY (LabKey/Prime-seq) and
 * INGEST_URL (HTTP/HTTPS URLs). Use INGEST_FILE when samplesheet rows have a
 * non-empty 'path' column pointing to a local .rds (or .h5ad, .csv, .tsv, .txt) file.
 *
 * Requires no network access and no authentication. The file must exist at the
 * specified path before the process runs.
 */

process INGEST_FILE {
    tag 'ingest_file'
    label 'process_ingest_file'

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
    source_path    <- "${meta.path}"

    message("[INGEST_FILE] Processing sample: ", sample_id)
    message("[INGEST_FILE] species          : ", species)
    message("[INGEST_FILE] source_path      : ", source_path)

    if (!nzchar(source_path)) {
        stop("INGEST_FILE requires a non-empty 'path' column in the samplesheet.")
    }
    if (!file.exists(source_path)) {
        stop("[INGEST_FILE] Source file not found: ", source_path)
    }

    suffix <- tolower(tools::file_ext(source_path))
    message("[INGEST_FILE] Detected suffix  : ", suffix)

    out_path      <- paste0(sample_id, ".rds")
    metadata_path <- paste0(sample_id, "_metadata.csv")

    if (!suffix %in% c("rds", "rdata", "rda", "h5ad", "csv", "tsv", "txt")) {
        stop("Unsupported file extension '", suffix, "' for file: ", source_path)
    }

    if (suffix == "rds") {
        file.copy(from = source_path, to = out_path, overwrite = TRUE)
        seurat_obj <- readRDS(out_path)
    } else if (suffix %in% c("csv", "tsv", "txt")) {
        message("[INGEST_FILE] Building Seurat object from a count matrix: ", source_path)
        counts <- data.table::fread(source_path, data.table = FALSE)
        row.names(counts) <- counts[[1]]
        counts[[1]] <- NULL
        counts <- as.matrix(counts)
        seurat_obj <- CreateSeuratObject(
            counts = counts,
            project = sample_id,
            min.cells = 0,
            min.features = 0
        )
        message("[INGEST_FILE] Built Seurat object with ", ncol(seurat_obj),
                " cells and ", nrow(seurat_obj), " genes.")
    } else if (suffix == "h5ad") {
        message("[INGEST_FILE] Converting h5ad to Seurat via reticulate...")
        if (!requireNamespace("anndata", quietly = TRUE)) {
            stop("Package 'anndata' is required for .h5ad file processing.")
        }
        ad <- anndata::read_h5ad(source_path)
        seurat_obj <- CreateSeuratObject(
            counts = t(as.matrix(ad\$X)),
            project = sample_id,
            min.cells = 0,
            min.features = 0
        )
        message("[INGEST_FILE] Converted h5ad to Seurat: ", ncol(seurat_obj),
                " cells, ", nrow(seurat_obj), " genes.")
    } else {
        file.copy(from = source_path, to = out_path, overwrite = TRUE)
        seurat_obj <- readRDS(out_path)
    }

    if (!inherits(seurat_obj, "Seurat")) {
        stop("Loaded object is not a Seurat instance for sample: ", sample_id)
    }

    seurat_obj[["sample_id"]] <- sample_id
    seurat_obj[["species"]] <- species
    seurat_obj[["source_path"]] <- source_path

    saveRDS(seurat_obj, file = out_path)
    metadata_df <- seurat_obj@meta.data
    metadata_df[["sample_id"]] <- sample_id
    metadata_df[["species"]] <- species
    metadata_df[["source_path"]] <- source_path
    utils::write.csv(metadata_df, file = metadata_path, row.names = TRUE)

    message("[INGEST_FILE] Cells loaded: ", ncol(seurat_obj))
    message("[INGEST_FILE] Genes loaded: ", nrow(seurat_obj))
    message("[INGEST_FILE] Saved Seurat object to: ", out_path)
    message("[INGEST_FILE] Saved metadata table to: ", metadata_path)
    """

    stub:
    """
    touch "${meta.id}.rds"
    touch "${meta.id}_metadata.csv"
    """
}