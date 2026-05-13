#!/usr/bin/env bash
# fetch_example_data.sh — Download pbmc3k and split into 3 pseudo-species test datasets
#
# USAGE:
#   cd template/gw
#   bash fetch_example_data.sh [N_GENES]
#
#   N_GENES  Number of top highly-variable genes to retain before splitting
#            (default: 500).  Set to 0 to keep all genes.
#
#            WHY THIS EXISTS:
#            pbmc3k has ~13,714 genes; after babelgene ortholog renaming and
#            mygene HomoloGene intersection across human/macaque/mouse, the
#            shared feature matrix ends up at ~8,134 genes.  scMODAL's geometric
#            loss materialises a (batch, batch, n_genes) float32 tensor *per
#            species* for the autograd backward pass, so 3 species × 8,134 genes
#            requires ~7.9 GiB of VRAM just for those intermediates — exceeding
#            the 7.66 GiB total on an RTX 3070.
#
#            For LOCAL TESTING only, we subset to the top N HVGs before
#            splitting so the shared gene space stays small.  For PRODUCTION
#            (e.g. A100 80 GB cards), pass N_GENES=0 or a large value.
#
#            The HVG subset is applied to the full merged object BEFORE
#            splitting into pseudo-species, so all three subsets share the
#            same starting gene universe.  babelgene then maps those human
#            symbols to macaque/mouse orthologs, and GENE_HARMONIZE intersects
#            whatever passes — preserving the homolog-alignment contract.
#
# This script:
#   1. Downloads the pbmc3k Seurat object from the public SeuratData repository
#   2. Optionally subsets to top N HVGs (controlled by N_GENES above)
#   3. Splits cells into 3 pseudo-species subsets (human, macaque, mouse)
#   4. Saves each subset as a local RDS file in template/gw/data/
#   5. Generates samplesheet.csv with sample_id, path, species columns (path mode)
#
# The 3 subsets are created by splitting cells by cluster identity, simulating
# a cross-species integration scenario. This allows testing the full pipeline:
#   INGEST_FILE → EXPORT_COUNTS → GENE_HARMONIZE → SCMODAL_INTEGRATE
#
# Requires: R with Seurat and SeuratData packages installed.
# If R is not available, this script will attempt to install it via conda/mamba.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# N_GENES: first positional arg, default 500 for local GPU testing.
# Pass 0 to disable subsetting (production / A100 use).
N_GENES="${1:-500}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${SCRIPT_DIR}/data"
SAMPLESHEET="${SCRIPT_DIR}/samplesheet.csv"

mkdir -p "${DATA_DIR}"

echo "=========================================="
echo " Fetch Example Data — pbmc3k → 3 pseudo-species"
if [ "${N_GENES}" -gt 0 ]; then
    echo " Gene subsetting: top ${N_GENES} HVGs (local GPU testing)"
else
    echo " Gene subsetting: DISABLED (all genes retained)"
fi
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

Rscript --no-save - "${DATA_DIR}" "${N_GENES}" <<'REOF'
args <- commandArgs(trailingOnly = TRUE)
data_dir <- args[1]
n_genes   <- as.integer(args[2])

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
message("[FETCH] Updating pbmc3k.final from v3 to v5 assay...")
pbmc <- Seurat::UpdateSeuratObject(pbmc3k.final)

message("[FETCH] Total cells: ", ncol(pbmc))
message("[FETCH] Total genes: ", nrow(pbmc))

# ---------------------------------------------------------------------------
# Optional HVG subsetting (for local GPU testing)
# ---------------------------------------------------------------------------
# This is applied to the FULL merged object before splitting so all three
# pseudo-species subsets start from the same gene universe.  babelgene then
# maps those human symbols to species-appropriate orthologs, and GENE_HARMONIZE
# intersects whatever survives — the homolog-alignment contract is preserved.
#
# Why HVGs rather than random genes: HVGs drive clustering and are more likely
# to have well-annotated orthologs in NCBI HomoloGene than lowly-expressed or
# non-variable genes.
if (!is.na(n_genes) && n_genes > 0 && n_genes < nrow(pbmc)) {
    message("[FETCH] Selecting top ", n_genes, " highly variable genes ...")
    pbmc <- Seurat::FindVariableFeatures(pbmc, selection.method = "vst",
                                         nfeatures = n_genes, verbose = FALSE)
    hvgs <- Seurat::VariableFeatures(pbmc)
    pbmc <- pbmc[hvgs, ]
    message("[FETCH] Gene count after HVG subsetting: ", nrow(pbmc))
} else {
    if (is.na(n_genes) || n_genes == 0) {
        message("[FETCH] HVG subsetting disabled — retaining all ", nrow(pbmc), " genes.")
    }
}

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

# babelgene expects specific species names. Map our short-form labels to
# the exact common/scientific names that babelgene recognizes.
SPECIES_ALIAS_MAP <- list(
    "macaque" = "rhesus macaque",
    "mouse"   = "mouse",
    "human"   = "human"
)

rename_genes_to_species <- function(obj, target_species, species_label) {
    human_genes <- rownames(obj)
    message("[FETCH] Renaming ", length(human_genes), " genes for ", species_label, "...")

    # Resolve alias to a babelgene-recognized species name
    babelgene_species <- SPECIES_ALIAS_MAP[[species_label]]
    if (is.null(babelgene_species)) {
        babelgene_species <- species_label
    }
    message("[FETCH] Using babelgene species name: ", babelgene_species)

    # Get human→target orthologs (one-to-one only, to avoid ambiguity)
    ortho <- tryCatch(
        babelgene::orthologs(
            genes = human_genes,
            species = babelgene_species,
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

# ---------------------------------------------------------------------------
# Inject RIRA-annotated metadata columns into all three subsets.
# Real pbmc3k has no RIRA columns — these simulate production metadata so
# the ingest_tabulate workflow can be end-to-end tested locally.
# ---------------------------------------------------------------------------

set.seed(42)

immune_levels <- c("Immune", "NonImmune")
immune_weights <- c(0.65, 0.35)

tnk_levels <- c("CD4_T", "CD8_T", "NK")
tnk_weights <- c(0.45, 0.35, 0.20)

myeloid_levels <- c("Monocyte", "Neutrophil", "DC", "MacroPhage")
myeloid_weights <- c(0.30, 0.35, 0.15, 0.20)

# Subject/Vaccine/Timepoint/Tissue: simulate a small cohort (8 subjects)
subject_pool <- sprintf("SUBJ%03d", 1:8)
vaccine_pool <- c("Placebo", "BNT162b2", "mRNA-1273")
timepoint_pool <- c("Baseline", "Week2", "Week4", "Week12")
tissue_pool <- c("PBMC")

assign_rira <- function(obj) {
    n <- ncol(obj)
    meta <- obj@meta.data
    meta$SubjectId <- sample(subject_pool, n, replace = TRUE)
    meta$Vaccine <- sample(vaccine_pool, n, replace = TRUE)
    meta$Timepoint <- sample(timepoint_pool, n, replace = TRUE)
    meta$Tissue <- sample(tissue_pool, n, replace = TRUE)
    meta$cDNA_ID <- paste0("cDNA_", seq_len(n))
    meta$RIRA_Immune.cellclass <- sample(immune_levels, n, replace = TRUE, prob = immune_weights)
    meta$RIRA_TNK_v2.cellclass <- sample(tnk_levels, n, replace = TRUE, prob = tnk_weights)
    meta$RIRA_Myeloid_v3.cellclass <- sample(myeloid_levels, n, replace = TRUE, prob = myeloid_weights)
    meta$RIRA_Immune.cellclass <- ifelse(
        meta$RIRA_Immune.cellclass == "NonImmune",
        NA_character_,
        meta$RIRA_Immune.cellclass
    )
    meta$RIRA_TNK_v2.cellclass <- ifelse(
        meta$RIRA_Immune.cellclass != "TNK",
        NA_character_,
        meta$RIRA_TNK_v2.cellclass
    )
    meta$RIRA_Myeloid_v3.cellclass <- ifelse(
        meta$RIRA_Immune.cellclass != "Myeloid",
        NA_character_,
        meta$RIRA_Myeloid_v3.cellclass
    )
    obj@meta.data <- meta
    obj
}

subset_a <- assign_rira(subset_a)
subset_b <- assign_rira(subset_b)
subset_c <- assign_rira(subset_c)

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

# Generate RIRA-annotated metadata CSVs for testing ingest_tabulate
gen_metadata_csv <- function(obj, data_dir, species_label) {
    meta <- obj@meta.data
    required_cols <- c("barcode", "cDNA_ID", "SubjectId", "Vaccine", "Timepoint", "Tissue",
                       "sample_id", "species", "RIRA_Immune.cellclass", "RIRA_TNK_v2.cellclass",
                       "RIRA_Myeloid_v3.cellclass")
    meta$barcode <- colnames(obj)
    meta$species <- species_label
    sample_id <- paste0("PBMC_", toupper(species_label))
    meta$sample_id <- sample_id
    meta <- meta[, colnames(meta) %in% required_cols | grepl("^RIRA", colnames(meta)) |
                     colnames(meta) %in% c("barcode", "cDNA_ID", "SubjectId", "Vaccine",
                                           "Timepoint", "Tissue", "sample_id", "species")]
    out_path <- file.path(data_dir, paste0(sample_id, "_metadata.csv"))
    write.csv(meta, file = out_path, row.names = FALSE)
    message("[FETCH] Saved metadata CSV: ", out_path, " (", nrow(meta), " rows, ", ncol(meta), " cols)")
    return(out_path)
}

meta_a <- gen_metadata_csv(subset_a, data_dir, "human")
meta_b <- gen_metadata_csv(subset_b, data_dir, "macaque")
meta_c <- gen_metadata_csv(subset_c, data_dir, "mouse")

message("[FETCH] Done!")
REOF

# --- Generate samplesheet.csv ---
echo ""
echo "--- Generating samplesheet.csv ---"

cat > "${SAMPLESHEET}" <<EOF
sample_id,output_file_id,url,path,species,SubjectId
PBMC_HUMAN,,,${DATA_DIR}/pbmc3k_human.rds,human,SUBJ001
PBMC_MACAQUE,,,${DATA_DIR}/pbmc3k_macaque.rds,macaque,SUBJ002
PBMC_MOUSE,,,${DATA_DIR}/pbmc3k_mouse.rds,mouse,SUBJ003
EOF

echo -e "${GREEN}Samplesheet created: ${SAMPLESHEET}${NC}"
echo ""
echo "Contents:"
cat "${SAMPLESHEET}"

# --- Generate tabulate_samplesheet.csv for testing ingest_tabulate workflow ---
TABULATE_SAMPLESHEET="${SCRIPT_DIR}/tabulate_samplesheet.csv"

cat > "${TABULATE_SAMPLESHEET}" <<EOF
sample_id,metadata_path,species
PBMC_HUMAN,${DATA_DIR}/PBMC_HUMAN_metadata.csv,human
PBMC_MACAQUE,${DATA_DIR}/PBMC_MACAQUE_metadata.csv,macaque
PBMC_MOUSE,${DATA_DIR}/PBMC_MOUSE_metadata.csv,mouse
EOF

echo ""
echo -e "${GREEN}Tabulate samplesheet created: ${TABULATE_SAMPLESHEET}${NC}"
echo ""
echo "Contents:"
cat "${TABULATE_SAMPLESHEET}"

# --- Generate NMF-VAE test data: split human pbmc3k into two SubjectIds ---
# NMF-VAE requires shared genes across samples. Cross-species splits (human/macaque/mouse)
# have disjoint gene sets after ortholog renaming. For local testing, we split the human
# subset into two halves — both human, so genes are 100% shared.
echo ""
echo "--- Generating NMF-VAE test data (human split into 2 SubjectIds) ---"

Rscript --no-save - "${DATA_DIR}" <<'REOF'
args <- commandArgs(trailingOnly = TRUE)
data_dir <- args[1]

suppressPackageStartupMessages({
    library(Seurat)
})

# Load the human subset we just saved
human_rds <- file.path(data_dir, "pbmc3k_human.rds")
if (!file.exists(human_rds)) {
    stop("pbmc3k_human.rds not found — run fetch_example_data.sh without interrupting.")
}
obj <- readRDS(human_rds)
message("[NMF] Loaded human subset: ", ncol(obj), " cells, ", nrow(obj), " genes")

# Split cells into two groups by SubjectId (hash-based, reproducible)
meta <- obj@meta.data
subject_ids <- unique(meta$SubjectId)
set.seed(99)
subject_ids <- sample(subject_ids)
half <- ceiling(length(subject_ids) / 2)
group_a_subjects <- subject_ids[1:half]
group_b_subjects <- subject_ids[(half + 1):length(subject_ids)]

meta$group <- ifelse(meta$SubjectId %in% group_a_subjects, "A", "B")

cells_a <- colnames(obj)[meta$group == "A"]
cells_b <- colnames(obj)[meta$group == "B"]

message("[NMF] Group A: ", length(cells_a), " cells (", length(group_a_subjects), " subjects)")
message("[NMF] Group B: ", length(cells_b), " cells (", length(group_b_subjects), " subjects)")

# Subset and assign cDNA_ID
nmf_a <- subset(obj, cells = cells_a)
nmf_a@meta.data$sample_id <- "PBMC_SUBJ_A"
nmf_b <- subset(obj, cells = cells_b)
nmf_b@meta.data$sample_id <- "PBMC_SUBJ_B"

# Save
path_a <- file.path(data_dir, "pbmc3k_nmf_subjA.rds")
path_b <- file.path(data_dir, "pbmc3k_nmf_subjB.rds")
saveRDS(nmf_a, file = path_a)
saveRDS(nmf_b, file = path_b)
message("[NMF] Saved: ", path_a, " (", ncol(nmf_a), " cells)")
message("[NMF] Saved: ", path_b, " (", ncol(nmf_b), " cells)")
REOF

# --- Generate nmf_vae_samplesheet.csv ---
NMF_SAMPLESHEET="${SCRIPT_DIR}/nmf_vae_samplesheet.csv"

cat > "${NMF_SAMPLESHEET}" <<EOF
sample_id,species,path,lambda_graph
PBMC_SUBJ_A,human,${DATA_DIR}/pbmc3k_nmf_subjA.rds,moderate
PBMC_SUBJ_B,human,${DATA_DIR}/pbmc3k_nmf_subjB.rds,moderate
EOF

echo ""
echo -e "${GREEN}NMF-VAE samplesheet created: ${NMF_SAMPLESHEET}${NC}"
echo ""
echo "Contents:"
cat "${NMF_SAMPLESHEET}"

# --- tcr_epitope: toy TCR metadata + epitope FASTA + samplesheet ---
# Generates toy TRA/TRB clone data from the PBMC human subset (or standalone).
# Also generates epitopes.fasta from TDC (if available) or synthetic HLA panel.
# Optionally pre-trains the XGBoost binding model if FETCH_TRAIN_MODEL=true.

TCR_EPITOPE_DATA="${DATA_DIR}/tcr_epitope"
TCR_SAMPLESHEET="${SCRIPT_DIR}/tcr_epitope_samplesheet.csv"
mkdir -p "${TCR_EPITOPE_DATA}"

echo "[FETCH] Creating toy TCR metadata..."

python3 - <<'PYEOF'
import os, sys, random
from pathlib import Path

data_dir = Path(os.environ.get("DATA_DIR", "template/gw/data"))
out_dir = data_dir / "tcr_epitope"
out_dir.mkdir(parents=True, exist_ok=True)
rng = random.Random(42)

def make_cdr3(rng, length=None):
    length = length or rng.randint(10, 16)
    aa = "ACDEFGHIKLMNPQRSTVWY"
    return "".join(rng.choice(aa) for _ in range(length))

# --- Generate toy merged TCR metadata ---
# In production this comes from QUANTIFY_TCR → tcrClustR output.
# For local testing we generate plausible synthetic clones.
records = []
subject_pool = [f"SUBJ{i:03d}" for i in range(1, 9)]
TRA_V_pool = ["TRAV12-2*01","TRAV19*01","TRAV27*01","TRAV6*01","TRAV14*01"]
TRA_J_pool = ["TRAJ33*01","TRAJ37*01","TRAJ20*01","TRAJ28*01"]
TRB_V_pool = ["TRBV6-1*01","TRBV12-3*01","TRBV27*01","TRBV4-1*01","TRBV3-1*01"]
TRB_J_pool = ["TRBJ2-1*01","TRBJ1-1*01","TRBJ2-7*01","TRBJ2-3*01"]

for clone_idx in range(100):
    tra = make_cdr3(rng)
    trb = make_cdr3(rng)
    n_cells = rng.randint(3, 20)
    for cell_idx in range(n_cells):
        records.append({
            "barcode": f"BC_{clone_idx:04d}_{cell_idx:04d}",
            "SubjectId": rng.choice(subject_pool),
            "TRA": tra, "TRB": trb,
            "TRA_V": rng.choice(TRA_V_pool), "TRA_J": rng.choice(TRA_J_pool),
            "TRB_V": rng.choice(TRB_V_pool), "TRB_J": rng.choice(TRB_J_pool),
            "TRA_CloneIdx": clone_idx, "TRA_CloneSize": n_cells,
            "TRB_CloneIdx": clone_idx, "TRB_CloneSize": n_cells,
        })

import pandas as pd
df = pd.DataFrame(records)
out_csv = out_dir / "toy_tcr_metadata.csv"
df.to_csv(out_csv, index=False)
print(f"[FETCH] Toy TCR metadata: {out_csv} ({len(df)} cells, {df['TRA_CloneIdx'].nunique()} clones)")

# --- Generate epitopes.fa ---
has_tdc = False
try:
    import tdc; has_tdc = True
except Exception:
    pass

if has_tdc:
    print("[FETCH] TDC available — fetching Weber epitope set...")
    try:
        from tdc.multi_pred import TCREpitopeBinding
        cache = Path("/tmp/tdc_cache_tcr"); cache.mkdir(parents=True, exist_ok=True)
        data = TCREpitopeBinding(name="weber", path=str(cache))
        split = data.get_split(method="random", seed=816, frac=[0.7, 0.1, 0.2])
        uniq = {}
        for df_key in ["train","val","test"]:
            for _, row in split[df_key].iterrows():
                epi = str(row["epitope_aa"])
                if epi not in uniq:
                    uniq[epi] = len(uniq)
        fasta = out_dir / "epitopes.fa"
        with open(fasta, "w") as fh:
            for seq, idx in uniq.items():
                fh.write(f">epitope_{idx:04d}\n{seq}\n")
        print(f"[FETCH] epitopes.fa (TDC Weber): {fasta} ({len(uniq)} unique epitopes)")
    except Exception as e:
        print(f"[FETCH] TDC fetch error: {e} — falling back to synthetic panel")
        has_tdc = False

if not has_tdc:
    epitopes = [
        ("epitope_0001","GLCTLVAML"),  ("epitope_0002","NLVPMVATV"),
        ("epitope_0003","GILGFVFTL"),  ("epitope_0004","FLYIGGCLI"),
        ("epitope_0005","AMGIHTSVL"),  ("epitope_0006","IMQDGIVGV"),
        ("epitope_0007","CTDVGDSTL"),  ("epitope_0008","KLGEFVNIV"),
        ("epitope_0009","NLVPMIAATV"), ("epitope_0010","FMYDGLNQI"),
        ("epitope_0011","TPRVTGDG"),   ("epitope_0012","FMYDGNGI"),
    ]
    fasta = out_dir / "epitopes.fa"
    with open(fasta, "w") as fh:
        for eid, seq in epitopes:
            fh.write(f">{eid}\n{seq}\n")
    print(f"[FETCH] epitopes.fa (synthetic): {fasta} ({len(epitopes)} epitopes)")

# --- Optionally pre-train binding model ---
if os.environ.get("FETCH_TRAIN_MODEL") == "true":
    print("[FETCH] FETCH_TRAIN_MODEL=true — training binding model...")
    import subprocess, shutil
    script = Path(os.environ.get("SCRIPT_DIR",".")).parent / "scripts" / "train_tcr_epitope_binding.py"
    out_models = Path(data_dir.parent) / "tcr_epitope_models"
    if script.exists():
        r = subprocess.run([
            "python3", str(script), "--output-dir", str(out_models),
            "--local-gpu", "--esm2-model", "esm2_t6_8M_UR50D"
        ], capture_output=True, text=True, timeout=3600)
        if r.returncode == 0:
            print(f"[FETCH] Binding model trained: {out_models}")
        else:
            print(f"[FETCH] Training failed (non-fatal):\n{r.stderr[-400:]}")
    else:
        print(f"[FETCH] Training script not found: {script} — skipping")
PYEOF

cat > "${TCR_SAMPLESHEET}" <<EOF
sample_id,epitope_file,path
toy_tcr,${TCR_EPITOPE_DATA}/epitopes.fa,${TCR_EPITOPE_DATA}/toy_tcr_metadata.csv
EOF
echo -e "${GREEN}[FETCH] tcr_epitope samplesheet: ${TCR_SAMPLESHEET}${NC}"

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
if [ "${N_GENES}" -gt 0 ]; then
    echo "Gene subsetting: top ${N_GENES} HVGs"
    echo "  → safe for local GPU testing (RTX 3070 / 8 GB VRAM)"
    echo "  → for production A100 runs, re-fetch with: bash fetch_example_data.sh 0"
else
    echo "Gene subsetting: disabled (all genes retained)"
fi
echo ""
echo "Next: run a workflow"
echo "  bash run.sh --workflow ingest_export"
echo "  bash run.sh --workflow integration"
echo "  bash run.sh --workflow ingest_tabulate --input ${TABULATE_SAMPLESHEET}"
echo "  bash run.sh --workflow nmf_vae --input ${NMF_SAMPLESHEET}"
echo "  bash run.sh --workflow gex_mil"
echo "  bash run.sh --workflow tcr_mil"
echo "  bash run.sh --workflow tcr_epitope --input ${TCR_SAMPLESHEET} --binding_model_path tcr_epitope_models"
echo "=========================================="