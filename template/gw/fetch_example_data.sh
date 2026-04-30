#!/usr/bin/env bash
# fetch_example_data.sh — Download pbmc3k and split into 3 pseudo-species test datasets
#
# USAGE:
#   cd template/gw
#   bash fetch_example_data.sh
#
# This script:
#   1. Downloads the pbmc3k Seurat object from the public SeuratData repository
#   2. Splits cells into 3 pseudo-species subsets (human, macaque, mouse)
#   3. Saves each subset as a local RDS file in template/gw/data/
#   4. Generates samplesheet.csv with sample_id, url, species columns
#
# The 3 subsets are created by splitting cells by cluster identity, simulating
# a cross-species integration scenario. This allows testing the full pipeline:
#   INGEST (URL) → EXPORT_COUNTS → GENE_HARMONIZE → SCMODAL_INTEGRATE
#
# Requires: R with Seurat and SeuratData packages installed.
# If R is not available, this script will attempt to install it via conda/mamba.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${SCRIPT_DIR}/data"
SAMPLESHEET="${SCRIPT_DIR}/samplesheet.csv"

mkdir -p "${DATA_DIR}"

echo "=========================================="
echo " Fetch Example Data — pbmc3k → 3 pseudo-species"
echo "=========================================="

# --- Check for R ---
if ! command -v Rscript &>/dev/null; then
    echo -e "${RED}ERROR: R is not installed or not on PATH.${NC}"
    echo ""
    echo "On Bazzite, install R with:"
    echo "  rpm-ostree install R"
    echo ""
    echo "Or use conda/mamba:"
    echo "  conda install -c conda-forge r-base r-seurat r-seuratdata"
    exit 1
fi

echo -e "${GREEN}R found: $(Rscript --version 2>&1 | head -1)${NC}"

# --- Check for required R packages ---
echo ""
echo "--- Checking R packages ---"

Rscript -e '
pkgs <- c("Seurat", "SeuratData", "babelgene")
missing <- pkgs[!sapply(pkgs, requireNamespace, quietly = TRUE)]
if (length(missing) > 0) {
    cat("MISSING:", paste(missing, collapse = ", "), "\n")
    quit(status = 1)
} else {
    cat("All required packages are installed.\n")
    quit(status = 0)
}
' || {
    echo -e "${YELLOW}Installing missing R packages...${NC}"
    Rscript -e '
    if (!requireNamespace("remotes", quietly = TRUE)) install.packages("remotes", repos = "https://cloud.r-project.org")
    if (!requireNamespace("Seurat", quietly = TRUE)) install.packages("Seurat", repos = "https://cloud.r-project.org")
    if (!requireNamespace("SeuratData", quietly = TRUE)) remotes::install_github("satijalab/seurat-data")
    if (!requireNamespace("babelgene", quietly = TRUE)) install.packages("babelgene", repos = "https://cloud.r-project.org")
    ' || {
        echo -e "${RED}ERROR: Failed to install R packages.${NC}"
        echo "Try installing manually:"
        echo "  R -e 'install.packages(c(\"Seurat\", \"babelgene\"), repos = \"https://cloud.r-project.org\")'"
        echo "  R -e 'remotes::install_github(\"satijalab/seurat-data\")'"
        exit 1
    }
}

# --- Download and split pbmc3k ---
echo ""
echo "--- Downloading pbmc3k dataset ---"

Rscript --no-save - "${DATA_DIR}" <<'REOF'
args <- commandArgs(trailingOnly = TRUE)
data_dir <- args[1]

suppressPackageStartupMessages({
    library(Seurat)
    library(SeuratData)
    library(babelgene)
})

message("[FETCH] Installing pbmc3k dataset (one-time download)...")
options(timeout = 300)
InstallData("pbmc3k")

message("[FETCH] Loading pbmc3k...")
data("pbmc3k")
pbmc <- pbmc3k.final

message("[FETCH] Total cells: ", ncol(pbmc))
message("[FETCH] Total genes: ", nrow(pbmc))

# Split cells into 3 groups by seurat_clusters
clusters <- as.character(pbmc$seurat_clusters)
unique_clusters <- sort(unique(clusters))
n_clusters <- length(unique_clusters)

message("[FETCH] Unique clusters: ", n_clusters)

# Assign clusters to 3 pseudo-species groups (round-robin)
group_a <- unique_clusters[seq(1, n_clusters, by = 3)]
group_b <- unique_clusters[seq(2, n_clusters, by = 3)]
group_c <- unique_clusters[seq(3, n_clusters, by = 3)]

cells_a <- colnames(pbmc)[clusters %in% group_a]
cells_b <- colnames(pbmc)[clusters %in% group_b]
cells_c <- colnames(pbmc)[clusters %in% group_c]

message("[FETCH] Group A (human)  : ", length(cells_a), " cells, clusters: ", paste(group_a, collapse = ","))
message("[FETCH] Group B (macaque): ", length(cells_b), " cells, clusters: ", paste(group_b, collapse = ","))
message("[FETCH] Group C (mouse)  : ", length(cells_c), " cells, clusters: ", paste(group_c, collapse = ","))

# Subset
subset_a <- subset(pbmc, cells = cells_a)
subset_b <- subset(pbmc, cells = cells_b)
subset_c <- subset(pbmc, cells = cells_c)

# Add species metadata
subset_a$species <- "human"
subset_b$species <- "macaque"
subset_c$species <- "mouse"

# --- Rename genes for non-human subsets using ortholog mapping ---
# GENE_HARMONIZE uses mygene to query gene symbols against each species' taxonomy ID.
# pbmc3k has human gene symbols. If we label a subset as "macaque" but keep human
# gene names, mygene will query human symbols against macaque taxid (9544) and find
# few/no matches. We must rename genes to species-appropriate orthologs.
#
# babelgene::orthologs() provides pre-computed human→other_species ortholog tables
# from the HGNC Comparison of Orthology Predictions (HCOP) database.

rename_genes_to_species <- function(obj, target_species, species_label) {
    human_genes <- rownames(obj)
    message("[FETCH] Renaming ", length(human_genes), " genes for ", species_label, "...")

    # Get human→target orthologs (one-to-one only, to avoid ambiguity)
    ortho <- tryCatch(
        babelgene::orthologs(
            genes = human_genes,
            species = target_species,
            human = TRUE,
            min_support = 1  # accept any support level to maximize coverage
        ),
        error = function(e) {
            message("[FETCH] WARNING: babelgene::orthologs() failed: ", e$message)
            return(NULL)
        }
    )

    if (is.null(ortho) || nrow(ortho) == 0) {
        message("[FETCH] WARNING: No orthologs found for ", species_label,
                ". Keeping human gene names (pipeline may fail at GENE_HARMONIZE).")
        return(obj)
    }

    # Deduplicate: keep first ortholog per human gene
    ortho <- ortho[!duplicated(ortho$human_symbol), ]

    # Build mapping: human_symbol → target_symbol
    gene_map <- setNames(ortho$symbol, ortho$human_symbol)

    # Which human genes have an ortholog?
    mappable <- human_genes %in% names(gene_map)
    n_mapped <- sum(mappable)
    message("[FETCH] Mapped ", n_mapped, "/", length(human_genes),
            " genes to ", species_label, " orthologs (",
            round(100 * n_mapped / length(human_genes), 1), "%)")

    if (n_mapped == 0) {
        message("[FETCH] WARNING: No genes could be mapped. Keeping human gene names.")
        return(obj)
    }

    # Subset to mappable genes only (drop unmapped genes)
    obj <- obj[mappable, ]

    # Rename features
    new_names <- gene_map[rownames(obj)]
    # Ensure uniqueness (append suffix for any collisions)
    dupes <- duplicated(new_names)
    if (any(dupes)) {
        new_names[dupes] <- paste0(new_names[dupes], "_dup", seq_len(sum(dupes)))
    }
    rownames(obj) <- new_names

    message("[FETCH] Final gene count for ", species_label, ": ", nrow(obj))
    return(obj)
}

# Human subset: keep original gene names (no renaming needed)
message("[FETCH] Human subset: keeping original human gene names (", nrow(subset_a), " genes)")

# Macaque subset: rename human genes → macaque orthologs
subset_b <- rename_genes_to_species(subset_b, "macaque", "macaque")

# Mouse subset: rename human genes → mouse orthologs
subset_c <- rename_genes_to_species(subset_c, "mouse", "mouse")

# Save RDS files
path_a <- file.path(data_dir, "pbmc3k_human.rds")
path_b <- file.path(data_dir, "pbmc3k_macaque.rds")
path_c <- file.path(data_dir, "pbmc3k_mouse.rds")

saveRDS(subset_a, file = path_a)
saveRDS(subset_b, file = path_b)
saveRDS(subset_c, file = path_c)

message("[FETCH] Saved: ", path_a, " (", ncol(subset_a), " cells, ", nrow(subset_a), " genes)")
message("[FETCH] Saved: ", path_b, " (", ncol(subset_b), " cells, ", nrow(subset_b), " genes)")
message("[FETCH] Saved: ", path_c, " (", ncol(subset_c), " cells, ", nrow(subset_c), " genes)")

message("[FETCH] Done!")
REOF

# --- Generate samplesheet.csv ---
echo ""
echo "--- Generating samplesheet.csv ---"

cat > "${SAMPLESHEET}" <<EOF
sample_id,url,species
PBMC_HUMAN,${DATA_DIR}/pbmc3k_human.rds,human
PBMC_MACAQUE,${DATA_DIR}/pbmc3k_macaque.rds,macaque
PBMC_MOUSE,${DATA_DIR}/pbmc3k_mouse.rds,mouse
EOF

echo -e "${GREEN}Samplesheet created: ${SAMPLESHEET}${NC}"
echo ""
echo "Contents:"
cat "${SAMPLESHEET}"

# --- Summary ---
echo ""
echo "=========================================="
echo " Example Data Ready"
echo "=========================================="
echo ""
echo "Data files:"
ls -lh "${DATA_DIR}/"*.rds 2>/dev/null || echo "  (no RDS files found — check R output above)"
echo ""
echo "Samplesheet: ${SAMPLESHEET}"
echo ""
echo "Next: run a workflow"
echo "  bash run.sh --workflow ingest_export"
echo "  bash run.sh --workflow integration"
echo "=========================================="