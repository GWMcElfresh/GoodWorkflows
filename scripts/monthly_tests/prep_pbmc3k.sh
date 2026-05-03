#!/usr/bin/env bash
# prep_pbmc3k.sh — Download pbmc3k, split into 3 pseudo-species, serve via HTTP
#
# Prepares test data for monthly workflow tests. Uses the same R processing
# pipeline as template/gw/fetch_example_data.sh, then serves the resulting
# .rds files via a local Python HTTP server so INGEST_URL can download them.
#
# USAGE:
#   bash scripts/monthly_tests/prep_pbmc3k.sh [N_GENES] [PORT]
#
#   N_GENES  Top HVGs to retain (default: 500 for local GPU, 0 for all genes)
#   PORT     HTTP server port (default: auto-detected free port)
#
# ENV vars set on success (source the script or parse output):
#   GW_TEST_BASE_URL    — e.g. http://127.0.0.1:18732
#   GW_TEST_SERVER_PID  — PID of the background HTTP server
#   GW_TEST_DATA_DIR    — absolute path to scripts/monthly_tests/data/

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

N_GENES="${1:-500}"
REQUESTED_PORT="${2:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DATA_DIR="${SCRIPT_DIR}/data"
SERVER_PID_FILE="${SCRIPT_DIR}/.http_server.pid"

mkdir -p "${DATA_DIR}"

echo "=========================================="
echo " Prep pbmc3k Test Data"
echo "=========================================="
echo " Pipeline root  : ${PIPELINE_ROOT}"
echo " Data dir       : ${DATA_DIR}"
echo " Gene subset    : ${N_GENES} HVGs (0=all)"
echo "=========================================="

# --- Container runtime ---
if command -v podman &>/dev/null; then
    CONTAINER_CMD="podman"
elif command -v docker &>/dev/null; then
    CONTAINER_CMD="docker"
else
    echo -e "${RED}ERROR: Neither podman nor docker found.${NC}"
    exit 1
fi
echo -e "${GREEN}Container runtime: ${CONTAINER_CMD}${NC}"

RDICVR_IMAGE="ghcr.io/bimberlabinternal/rdiscvr:latest"

# --- Idempotent: skip if data exists ---
ALL_EXIST=true
for f in pbmc3k_human.rds pbmc3k_macaque.rds pbmc3k_mouse.rds; do
    if [[ ! -f "${DATA_DIR}/${f}" ]]; then
        ALL_EXIST=false
        break
    fi
done

if [[ "${ALL_EXIST}" == "true" ]]; then
    echo ""
    echo -e "${YELLOW}Data files already exist — skipping R processing.${NC}"
    echo "  pbmc3k_human.rds:   $(ls -lh "${DATA_DIR}/pbmc3k_human.rds" | awk '{print $5}')"
    echo "  pbmc3k_macaque.rds: $(ls -lh "${DATA_DIR}/pbmc3k_macaque.rds" | awk '{print $5}')"
    echo "  pbmc3k_mouse.rds:   $(ls -lh "${DATA_DIR}/pbmc3k_mouse.rds" | awk '{print $5}')"
    echo "To re-fetch: delete ${DATA_DIR}/*.rds or run with -- --refetch"
else
    # --- Ensure container image ---
    if ! ${CONTAINER_CMD} image inspect "${RDICVR_IMAGE}" &>/dev/null; then
        echo ""
        echo -e "${YELLOW}Pulling ${RDICVR_IMAGE}...${NC}"
        ${CONTAINER_CMD} pull "${RDICVR_IMAGE}"
    fi

    echo ""
    echo "--- Processing pbmc3k (R inside container) ---"

    ${CONTAINER_CMD} run --rm \
        -v "${DATA_DIR}:/data:rw" \
        "${RDICVR_IMAGE}" \
        Rscript --no-save - "/data" "${N_GENES}" <<'REOF'
args <- commandArgs(trailingOnly = TRUE)
data_dir <- args[1]
n_genes   <- as.integer(args[2])

suppressPackageStartupMessages({
    library(Seurat)
    library(SeuratData)
    library(babelgene)
})

message("[PREP] Installing pbmc3k (one-time download)...")
options(timeout = 300)
InstallData("pbmc3k")

message("[PREP] Loading & updating pbmc3k.final to v5 assay...")
data("pbmc3k")
pbmc <- Seurat::UpdateSeuratObject(pbmc3k.final)
message("[PREP] Cells: ", ncol(pbmc), "  Genes: ", nrow(pbmc))

if (!is.na(n_genes) && n_genes > 0 && n_genes < nrow(pbmc)) {
    message("[PREP] Top ", n_genes, " HVGs...")
    pbmc <- Seurat::FindVariableFeatures(pbmc, selection.method = "vst",
                                         nfeatures = n_genes, verbose = FALSE)
    pbmc <- pbmc[Seurat::VariableFeatures(pbmc), ]
    message("[PREP] Genes after HVG: ", nrow(pbmc))
} else {
    message("[PREP] All genes retained (", nrow(pbmc), ")")
}

clusters <- as.character(pbmc$seurat_clusters)
uc <- sort(unique(clusters))
gc <- length(uc)
cells_a <- colnames(pbmc)[clusters %in% uc[seq(1, gc, by = 3)]]
cells_b <- colnames(pbmc)[clusters %in% uc[seq(2, gc, by = 3)]]
cells_c <- colnames(pbmc)[clusters %in% uc[seq(3, gc, by = 3)]]

message("[PREP] human=", length(cells_a), "  macaque=", length(cells_b), "  mouse=", length(cells_c))

sa <- subset(pbmc, cells = cells_a); sa$species <- "human"
sb <- subset(pbmc, cells = cells_b); sb$species <- "macaque"
sc <- subset(pbmc, cells = cells_c); sc$species <- "mouse"

SPECIES_ALIAS <- list(macaque = "rhesus macaque", mouse = "mouse", human = "human")

rename_species <- function(obj, label) {
    aliases <- if (!is.null(SPECIES_ALIAS[[label]])) SPECIES_ALIAS[[label]] else label
    genes <- rownames(obj)
    ortho <- tryCatch(babelgene::orthologs(genes, species = aliases,
                                           human = TRUE, min_support = 1),
                      error = function(e) { message("[PREP] babelgene failed: ", e$message); NULL })
    if (is.null(ortho) || nrow(ortho) == 0) {
        message("[PREP] No orthologs for ", label); return(obj)
    }
    ortho <- ortho[!duplicated(ortho$human_symbol), ]
    gmap <- setNames(ortho$symbol, ortho$human_symbol)
    ok <- genes %in% names(gmap)
    message("[PREP] ", label, ": ", sum(ok), "/", length(genes), " mapped")
    if (!any(ok)) return(obj)
    obj <- obj[ok, ]
    names <- gmap[rownames(obj)]
    dup <- duplicated(names)
    if (any(dup)) names[dup] <- paste0(names[dup], "_d", seq(sum(dup)))
    rownames(obj) <- names
    obj
}

sb <- rename_species(sb, "macaque")
sc <- rename_species(sc, "mouse")

saveRDS(sa, file.path(data_dir, "pbmc3k_human.rds"))
saveRDS(sb, file.path(data_dir, "pbmc3k_macaque.rds"))
saveRDS(sc, file.path(data_dir, "pbmc3k_mouse.rds"))
message("[PREP] Done. human=", nrow(sa), "/", ncol(sa),
        "  macaque=", nrow(sb), "/", ncol(sb),
        "  mouse=", nrow(sc), "/", ncol(sc))
REOF

    echo ""
    echo -e "${GREEN}Data preparation complete.${NC}"
    ls -lh "${DATA_DIR}"/pbmc3k_*.rds
fi

# --- Kill existing HTTP server ---
if [[ -f "${SERVER_PID_FILE}" ]]; then
    OLD_PID=$(cat "${SERVER_PID_FILE}")
    if kill -0 "${OLD_PID}" 2>/dev/null; then
        echo -e "${YELLOW}Stopping existing HTTP server (PID ${OLD_PID})...${NC}"
        kill "${OLD_PID}" 2>/dev/null || true
        sleep 1
    fi
    rm -f "${SERVER_PID_FILE}"
fi

# --- Find free port ---
if [[ "${REQUESTED_PORT}" -gt 0 ]]; then
    PORT="${REQUESTED_PORT}"
else
    PORT=$(python3 -c "import socket; s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()")
fi

echo ""
echo "--- Starting HTTP server on port ${PORT} ---"
cd "${DATA_DIR}"
python3 -m http.server "${PORT}" --bind 127.0.0.1 &
SERVER_PID=$!
echo "${SERVER_PID}" > "${SERVER_PID_FILE}"

# Wait for ready
for i in $(seq 1 10); do
    if curl -sf -o /dev/null "http://127.0.0.1:${PORT}/" 2>/dev/null; then
        echo -e "${GREEN}HTTP server ready (PID ${SERVER_PID})${NC}"
        break
    fi
    sleep 0.5
done

# Verify files
echo ""
echo "--- Verifying file access ---"
for f in pbmc3k_human.rds pbmc3k_macaque.rds pbmc3k_mouse.rds; do
    if curl -sf -o /dev/null "http://127.0.0.1:${PORT}/${f}" 2>/dev/null; then
        echo -e "  ${GREEN}OK${NC}  ${f}"
    else
        echo -e "  ${RED}FAIL${NC}  ${f}"
    fi
done

# --- Summary ---
BASE_URL="http://127.0.0.1:${PORT}"

# Persist for other scripts to read
echo "${BASE_URL}" > "${DATA_DIR}/base_url.txt"
echo "${PORT}" > "${DATA_DIR}/http_port.txt"
echo "${SERVER_PID}" > "${DATA_DIR}/http_server.pid"

echo ""
echo "=========================================="
echo " pbmc3k Test Data Ready"
echo "=========================================="
echo "  Base URL:  ${BASE_URL}"
echo "  PID:       ${SERVER_PID}"
echo "  Data dir:  ${DATA_DIR}"
echo "  Genes:     ${N_GENES} HVGs"
echo ""
echo "  export GW_TEST_BASE_URL=${BASE_URL}"
echo "  export GW_TEST_SERVER_PID=${SERVER_PID}"
echo "  export GW_TEST_DATA_DIR=${DATA_DIR}"
echo ""
echo "  To stop: kill ${SERVER_PID} && rm ${DATA_DIR}/http_server.pid"
echo "=========================================="
