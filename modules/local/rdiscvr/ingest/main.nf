/*
 * modules/local/rdiscvr/ingest/main.nf
 *
 * Process: INGEST
 * Container: ghcr.io/bimberlabinternal/rdiscvr:latest
 * Label: process_ingest  (4 CPUs, 32 GB, 4 h, partition=batch)
 *
 * Purpose:
 *   Use the Rdiscvr package to retrieve raw 10x Genomics count data and
 *   construct an initial Seurat object.  The resulting .rds file is the
 *   handoff artifact to SEURAT_PROCESS.
 *
 * Inputs:
 *   tuple val(meta), path(raw_data)
 *     meta.id   – sample identifier (used in output filenames and logs)
 *     raw_data  – path to the sample directory on the shared filesystem.
 *                 This must contain the standard 10x output layout:
 *                   raw_data/
 *                     barcodes.tsv.gz
 *                     features.tsv.gz  (or genes.tsv.gz)
 *                     matrix.mtx.gz
 *                 Alternatively raw_data may be a parent directory or any
 *                 path structure accepted by Rdiscvr::DownloadAndAppendCellBarcodes
 *                 or Seurat::Read10X – adjust the R script block accordingly.
 *
 * Outputs:
 *   tuple val(meta), path("${meta.id}.rds")  – emit: rds
 *     Serialised Seurat object written to the Nextflow work directory.
 *     Published to: <outdir>/ingest/<sample_id>/
 */

process INGEST {
    tag "${meta.id}"
    label 'process_ingest'

    container 'ghcr.io/bimberlabinternal/rdiscvr:latest'

    publishDir "${params.outdir}/ingest/${meta.id}", mode: 'copy'

    input:
    tuple val(meta), path(raw_data)

    output:
    tuple val(meta), path("${meta.id}.rds"), emit: rds

    // -------------------------------------------------------------------------
    // Stub – used by: nextflow run main.nf -stub-run
    // Creates zero-byte placeholder files so channel wiring can be validated
    // without executing containers or submitting real SLURM jobs.
    // -------------------------------------------------------------------------
    stub:
    """
    touch "${meta.id}.rds"
    """

    // -------------------------------------------------------------------------
    // Script
    // -------------------------------------------------------------------------
    script:
    """
    #!/usr/bin/env Rscript

    # Reproducibility: fail loudly on any error
    options(warn = 2)

    suppressPackageStartupMessages({
        library(Rdiscvr)
        library(Seurat)
    })

    sample_id <- "${meta.id}"
    raw_data  <- "${raw_data}"

    message("[INGEST] Processing sample: ", sample_id)
    message("[INGEST] Raw data path    : ", raw_data)

    # -------------------------------------------------------------------------
    # Load count matrix
    # Adjust the read strategy to match your data source:
    #   Option A – standard 10x CellRanger output directory
    #   Option B – Rdiscvr helper that fetches from a DISCVR-Seq server
    # -------------------------------------------------------------------------

    # Option A: Read directly from a local 10x directory
    counts <- Seurat::Read10X(data.dir = raw_data)

    # Option B (DISCVR-Seq): uncomment and replace Option A
    # counts <- Rdiscvr::GetCountData(sampleId = sample_id, outDir = raw_data)

    # -------------------------------------------------------------------------
    # Create Seurat object
    # min.cells / min.features are conservative defaults – adjust as needed.
    # -------------------------------------------------------------------------
    seurat_obj <- Seurat::CreateSeuratObject(
        counts      = counts,
        project     = sample_id,
        min.cells   = 3,
        min.features = 200
    )

    # Attach sample identity as metadata
    seurat_obj[["sample_id"]] <- sample_id

    # -------------------------------------------------------------------------
    # Basic QC metrics (does not filter – SEURAT_PROCESS applies actual cuts)
    # -------------------------------------------------------------------------
    seurat_obj[["percent.mt"]] <- Seurat::PercentageFeatureSet(
        seurat_obj,
        pattern = "^MT-"
    )

    message("[INGEST] Cells loaded: ", ncol(seurat_obj))
    message("[INGEST] Genes loaded: ", nrow(seurat_obj))

    # -------------------------------------------------------------------------
    # Save and exit
    # -------------------------------------------------------------------------
    out_path <- paste0(sample_id, ".rds")
    saveRDS(seurat_obj, file = out_path)
    message("[INGEST] Saved Seurat object to: ", out_path)
    """
}
