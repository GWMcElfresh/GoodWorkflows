#!/usr/bin/env Rscript
# Nextflow template: quantify_tcr.R
# QUANTIFY_TCR — clone quantification via tcrClustR::CalculateTcrDistances.
#
# Nextflow substitutions:
#   ${meta.id}                  — sample identifier
#   ${params.tcrChains}         — e.g. "TRA,TRB"
#   ${params.tcrMinimumCloneSize} — minimum clone size (default 2)
#   ${params.tcrOrganism}       — "human" or "mouse"

options(warn = 2)

suppressPackageStartupMessages({
    library(tcrClustR)
    library(Seurat)
})

sample_id <- "${meta.id}"
out_rds   <- paste0(sample_id, "_tcr.rds")
out_meta  <- paste0(sample_id, "_tcr_metadata.csv")

message("[QUANTIFY_TCR] Processing sample: ", sample_id)

seurat_obj <- readRDS("${rds}")

# ── Validate required metadata columns ──────────────────────────────────
required_cols <- c("SubjectId")
tcr_cols <- strsplit("${params.tcrChains}", ",")[[1]]
v_genes  <- paste0(tcr_cols, "_V")
j_genes  <- paste0(tcr_cols, "_J")
chain_cols <- unlist(lapply(tcr_cols, function(c) c(c, paste0(c, "_V"), paste0(c, "_J"))))

missing <- setdiff(c(required_cols, chain_cols), names(seurat_obj@meta.data))
if (length(missing) > 0) {
    stop("[QUANTIFY_TCR] Missing required metadata columns: ",
         paste(missing, collapse = ", "),
         ". Please ensure TCR data has been added to the Seurat object.")
}

# ── Run tcrdist3 + format metadata ──────────────────────────────────────
organism          <- "${params.tcrOrganism}"
minimumCloneSize  <- as.integer("${params.tcrMinimumCloneSize}")
calculatePairs    <- grepl("TRA", "${params.tcrChains}") && grepl("TRB", "${params.tcrChains}")

seurat_obj <- tcrClustR::CalculateTcrDistances(
    inputData            = seurat_obj@meta.data,
    organism             = organism,
    chains               = tcr_cols,
    minimumCloneSize     = minimumCloneSize,
    calculateChainPairs  = calculatePairs,
    verbose              = TRUE
)

# Restore into Seurat object
# CalculateTcrDistances returns the Seurat object with updated misc and metadata
if (!inherits(seurat_obj, "Seurat")) {
    seurat_obj <- seurat_obj\$seurat
}

# ── Optional: Dirichlet clustering for exploratory analysis ─────────────
if ("${params.tcrRunDirichlet}" == "true") {
    message("[QUANTIFY_TCR] Running Dirichlet clustering ...")
    dp <- tcrClustR::DirichletClusterAnalysis(
        seuratObj   = seurat_obj,
        assayName   = paste0(tcr_cols[1], "_cdr3"),
        splitField  = "SubjectId",
        maxSamples  = as.integer("${params.tcrDirichletMaxSamples}"),
        nIterations = as.integer("${params.tcrDirichletIterations}")
    )
    # Store result in misc
    seurat_obj@misc\$TCR_Dirichlet <- dp
    message("[QUANTIFY_TCR] Dirichlet clustering complete: ",
            length(dp\$cluster_summary\$cluster), " clusters detected.")
}

# ── Save enriched Seurat object ─────────────────────────────────────────
saveRDS(seurat_obj, out_rds)

# ── Export cell metadata with clone indices ─────────────────────────────
meta_out <- seurat_obj[[]]
# Select relevant clone columns
clone_cols <- grep("(CloneIdx|CloneSize|ValidForClustering)\$", names(meta_out), value = TRUE)
keep_cols <- c("barcode", "SubjectId", clone_cols)
keep_cols <- keep_cols[keep_cols %in% names(meta_out)]
data.table::fwrite(meta_out[, ..keep_cols], out_meta)

message("[QUANTIFY_TCR] Saved: ", out_rds)
message("[QUANTIFY_TCR] Saved: ", out_meta)
message("[QUANTIFY_TCR] Done.")
