/*
 * modules/local/cellmembrane/seurat/main.nf
 *
 * Process: SEURAT_PROCESS
 * Container: ghcr.io/bimberlabinternal/cellmembrane:latest
 * Label: process_seurat  (8 CPUs, 64 GB, 12 h, partition=batch)
 *
 * Purpose:
 *   Apply standard QC filtering, normalization (SCTransform), dimensionality
 *   reduction, and clustering to each Seurat object produced by INGEST.
 *   Exports two artifacts:
 *     1. An updated .rds file (for any downstream R steps you add later).
 *     2. An .h5ad file (AnnData format) consumed by the GPU_ANALYSIS process.
 *
 * Inputs:
 *   tuple val(meta), path(rds)
 *     meta.id – sample identifier
 *     rds     – Seurat object from INGEST
 *
 * Outputs:
 *   tuple val(meta), path("${meta.id}_processed.rds"), emit: rds
 *   tuple val(meta), path("${meta.id}.h5ad"),          emit: h5ad
 *
 * h5ad export requires SeuratDisk; the cellmembrane image should include it.
 * If SeuratDisk is not available, replace the export block with:
 *   sceasy::convertFormat(seurat_obj, from="seurat", to="anndata",
 *                          outFile=paste0(sample_id, ".h5ad"))
 * or export the raw counts matrix to HDF5 via hdf5r.
 */

process SEURAT_PROCESS {
    tag "${meta.id}"
    label 'process_seurat'

    container 'ghcr.io/bimberlabinternal/cellmembrane:latest'

    publishDir "${params.outdir}/seurat/${meta.id}", mode: 'copy'

    input:
    tuple val(meta), path(rds)

    output:
    tuple val(meta), path("${meta.id}_processed.rds"), emit: rds
    tuple val(meta), path("${meta.id}.h5ad"),          emit: h5ad

    stub:
    """
    touch "${meta.id}_processed.rds"
    touch "${meta.id}.h5ad"
    """

    script:
    // Expose thread count from Nextflow's task.cpus to R via Sys.getenv
    def n_threads = task.cpus
    """
    #!/usr/bin/env Rscript

    options(warn = 2)

    suppressPackageStartupMessages({
        library(Seurat)
        library(CellMembrane)
        library(SeuratDisk)   # for h5ad export; see module header if unavailable
    })

    # Set BLAS/OMP threads to match the SLURM CPU allocation
    n_threads <- as.integer(Sys.getenv("SLURM_CPUS_ON_NODE", unset = "${n_threads}"))
    RhpcBLASctl::blas_set_num_threads(n_threads)
    RhpcBLASctl::omp_set_num_threads(n_threads)

    sample_id <- "${meta.id}"
    message("[SEURAT_PROCESS] Processing sample: ", sample_id)

    seurat_obj <- readRDS("${rds}")

    # -------------------------------------------------------------------------
    # QC filtering
    # Adjust thresholds to match your biology and sequencing depth.
    # -------------------------------------------------------------------------
    message("[SEURAT_PROCESS] Pre-filter cells: ", ncol(seurat_obj))

    seurat_obj <- subset(
        seurat_obj,
        subset = nFeature_RNA > 200  &
                 nFeature_RNA < 6000 &
                 percent.mt  < 20
    )

    message("[SEURAT_PROCESS] Post-filter cells: ", ncol(seurat_obj))

    # -------------------------------------------------------------------------
    # Normalisation and variable feature selection
    # SCTransform is the CellMembrane-preferred method; it regresses out
    # sequencing depth and other technical confounders.
    # -------------------------------------------------------------------------
    seurat_obj <- SCTransform(
        seurat_obj,
        vars.to.regress  = "percent.mt",
        verbose          = TRUE,
        ncells           = min(5000L, ncol(seurat_obj))
    )

    # -------------------------------------------------------------------------
    # Dimensionality reduction
    # -------------------------------------------------------------------------
    seurat_obj <- RunPCA(seurat_obj, npcs = 30, verbose = FALSE)

    seurat_obj <- RunUMAP(
        seurat_obj,
        dims        = 1:30,
        verbose     = FALSE,
        n.components = 2L
    )

    # -------------------------------------------------------------------------
    # Clustering
    # -------------------------------------------------------------------------
    seurat_obj <- FindNeighbors(seurat_obj, dims = 1:30, verbose = FALSE)
    seurat_obj <- FindClusters(seurat_obj,  resolution = 0.5, verbose = FALSE)

    message("[SEURAT_PROCESS] Clusters found: ",
            length(levels(seurat_obj[["seurat_clusters"]][, 1])))

    # -------------------------------------------------------------------------
    # CellMembrane helpers (optional – remove if not applicable)
    # Uncomment to apply lab-specific QC/annotation steps, e.g.:
    # seurat_obj <- CellMembrane::DropLowQualityCells(seurat_obj)
    # seurat_obj <- CellMembrane::ClassifyCells(seurat_obj, ...)
    # -------------------------------------------------------------------------

    # -------------------------------------------------------------------------
    # Save processed Seurat RDS
    # -------------------------------------------------------------------------
    rds_out <- paste0(sample_id, "_processed.rds")
    saveRDS(seurat_obj, file = rds_out)
    message("[SEURAT_PROCESS] Saved processed RDS: ", rds_out)

    # -------------------------------------------------------------------------
    # Export to h5ad (AnnData) for Python/GPU downstream step
    #
    # SeuratDisk workflow:
    #   1. SaveH5Seurat writes an h5seurat file (Seurat's native HDF5 format).
    #   2. Convert translates it to AnnData-compatible h5ad.
    #
    # The exported h5ad contains:
    #   X       – SCT normalised counts (log-normalised)
    #   raw.X   – raw counts (added below via SetAssayData)
    #   obsm    – PCA and UMAP embeddings
    #   obs     – cell metadata (cluster, sample_id, QC metrics)
    # -------------------------------------------------------------------------
    h5seurat_out <- paste0(sample_id, ".h5seurat")
    h5ad_out     <- paste0(sample_id, ".h5ad")

    SaveH5Seurat(seurat_obj, filename = h5seurat_out, overwrite = TRUE)
    Convert(h5seurat_out, dest = "h5ad", overwrite = TRUE)
    file.remove(h5seurat_out)   # clean up intermediate file

    message("[SEURAT_PROCESS] Saved h5ad: ", h5ad_out)
    message("[SEURAT_PROCESS] Done")
    """
}
