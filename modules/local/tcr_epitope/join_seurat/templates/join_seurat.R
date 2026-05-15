# NUMBA_DISABLE_JIT=1
#!/usr/bin/env Rscript
# join_seurat.R — JOIN_SEURAT
# Joins TCR epitope clone results back to the original Seurat RDS.
#
# Inputs:
#   - seurat_rds:     original Seurat RDS (from QUANTIFY_TCR)
#   - clone_metadata: clone_metadata.parquet  (clonotype_id, umap_x, umap_y, cluster, n_cells)
#   - binding_scores: binding_scores.parquet (clone_id, pep_XXX_score, …)
#
# Outputs:
#   - annotated RDS with new columns:
#       tcr_umap_x, tcr_umap_y, tcr_cluster, tcr_n_cells
#       pep_<NAME>_score for each peptide in the epitope pool
#
# Join key: clonotype_id (Seurat TCR metadata) → fallback to SHA256(TRA|""|TRB)

suppressPackageStartupMessages({
    library(arrow)
    library(dplyr)
})

cat("[JOIN] Starting JOIN_SEURAT\n")

seurat_path    <- "${seurat_rds}"
clone_meta_csv <- "${clone_metadata}"
binding_csv    <- "${binding_scores}"
out_path       <- "${meta.id}_annotated.rds"
epitope_file   <- "${meta.epitope_file}"

cat("[JOIN] Seurat RDS:   ", seurat_path, "\n")
cat("[JOIN] Clone meta:   ", clone_meta_csv, "\n")
cat("[JOIN] Binding scores:", binding_csv, "\n")
cat("[JOIN] Epitope file:  ", epitope_file, "\n")
cat("[JOIN] Output:       ", out_path, "\n")

# ── Load clone metadata ──────────────────────────────────────────────────────
clone_meta <- arrow::read_parquet(clone_meta_csv)
cat("[JOIN] Clone metadata: ", nrow(clone_meta), " clones, cols:",
    paste(colnames(clone_meta), collapse=", "), "\n")

# ── Load binding scores ──────────────────────────────────────────────────────
binding <- arrow::read_parquet(binding_csv)
cat("[JOIN] Binding scores:", nrow(binding), " clones, cols:",
    paste(colnames(binding), collapse=", "), "\n")

# ── Determine which peptides are in THIS sample's pool ──────────────────────
# epitope_file is a FASTA; read peptide names from it
peptides_in_pool <- character(0)
if (file.exists(epitope_file) && file.size(epitope_file) > 0) {
    lines <- readLines(epitope_file, warn = FALSE)
    in_header <- FALSE
    for (line in lines) {
        line <- gsub("\r\$", "", line)
        if (grepl("^>", line)) {
            # Extract peptide name (first word after ">")
            name <- sub("^>", "", line)
            name <- strsplit(trimws(name), "\\s+")[[1]][1]
            peptides_in_pool <- c(peptides_in_pool, name)
        }
    }
}
cat("[JOIN] Peptides in this sample's pool:", length(peptides_in_pool), "\n")

# ── Filter binding scores to only peptides in this sample's pool ─────────────
# binding has columns: clone_id, epitope_0001, epitope_0002, …
# (Epitope columns named by their FASTA sequence ID)
if (nrow(binding) > 0 && length(peptides_in_pool) > 0) {
    pep_cols <- intersect(peptides_in_pool, colnames(binding))
    cat("[JOIN] Matching peptide columns in binding scores:", length(pep_cols), "\n")
    binding_filtered <- binding[, c("clone_id", pep_cols), drop=FALSE]
} else {
    cat("[JOIN] No matching peptide columns — binding_filtered will be empty\n")
    binding_filtered <- data.frame(clone_id = character(0))
}

# Rename epitope columns to pep_<NAME> format
if (ncol(binding_filtered) > 1) {
    pep_col_rename <- setNames(pep_cols, paste0("pep_", pep_cols))
    colnames(binding_filtered) <- ifelse(
        colnames(binding_filtered) %in% names(pep_col_rename),
        pep_col_rename[colnames(binding_filtered)],
        colnames(binding_filtered)
    )
}

# ── Merge clone metadata + binding scores on clone_id ───────────────────────
merged <- clone_meta
if (nrow(binding_filtered) > 1) {
    merged <- merge(merged, binding_filtered, by = "clone_id", all.x = TRUE)
}
cat("[JOIN] Merged clone table: ", nrow(merged), " rows, ", ncol(merged), " cols\n")

# ── Build clonotype_id → clone properties mapping ────────────────────────────
# Use clonotype_id as the join key to Seurat
# If clonotype_id is NA/missing in clone_meta, fall back to TRA|TRB hash
clone_lookup <- merged
if (!"clonotype_id" %in% colnames(clone_lookup)) {
    clone_lookup[["clonotype_id"]] <- NA_character_
}

# ── Load Seurat object ────────────────────────────────────────────────────────
cat("[JOIN] Loading Seurat object:", seurat_path, "\n")
seurat_obj <- readRDS(seurat_path)
cat("[JOIN] Seurat: ", ncol(seurat_obj), " cells, ", nrow(seurat_obj), " features\n")

# ── Determine join key in Seurat metadata ────────────────────────────────────
# clonotype_id should be present from tcrClustR quantification
meta_dt <- seurat_obj@meta.data
join_col <- if ("clonotype_id" %in% colnames(meta_dt)) {
    "clonotype_id"
} else if ("CloneIdx" %in% colnames(meta_dt)) {
    "CloneIdx"
} else {
    stop("Neither clonotype_id nor CloneIdx found in Seurat@meta.data. ",
         "Columns: ", paste(colnames(meta_dt), collapse=", "))
}
cat("[JOIN] Using join key: ", join_col, "\n")

# ── Build per-cell lookup from clone_lookup ─────────────────────────────────
# clone_lookup has clonotype_id, umap_x, umap_y, cluster, n_cells, pep_*_score
# For cells with clonotype_id = NA, these will be NA in the final object

# Create lookup vector for each column we want to add
add_cols <- setdiff(colnames(clone_lookup), c("clone_id", "clonotype_id"))

# Make a named vector / list for fast lookup by clonotype_id
# Handle clonotype_id NA → NA lookup gracefully
lookup_list <- lapply(add_cols, function(col) {
    setNames(clone_lookup[[col]], clone_lookup[["clonotype_id"]])
})

# Add columns to Seurat metadata
for (col in add_cols) {
    vec <- lookup_list[[col]]
    # Map from clonotype_id in metadata to value in clone_lookup
    cell_clonotypes <- meta_dt[[join_col]]
    # Match: if cell_clonotype is in names(vec), use vec[cell_clonotype], else NA
    new_vals <- ifelse(
        is.na(cell_clonotypes) | !(cell_clonotypes %in% names(vec)),
        NA_real_,
        as.numeric(vec[cell_clonotypes])
    )
    # For non-numeric cols (cluster, character), handle differently
    if (is.character(clone_lookup[[col]]) || is.factor(clone_lookup[[col]])) {
        new_vals <- ifelse(
            is.na(cell_clonotypes) | !(cell_clonotypes %in% names(vec)),
            NA_character_,
            as.character(vec[cell_clonotypes])
        )
    }
    meta_dt[[paste0("tcr_", col)]] <- new_vals
}

seurat_obj@meta.data <- meta_dt

# ── Save annotated RDS ───────────────────────────────────────────────────────
saveRDS(seurat_obj, file = out_path)
cat("[JOIN] Annotated RDS saved:", out_path, "\n")
cat("[JOIN] JOIN_SEURAT complete.\n")