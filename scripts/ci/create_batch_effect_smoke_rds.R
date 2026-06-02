#!/usr/bin/env Rscript
# Create batch_effect_assessments smoke RDS from PBMC3k with mocked RIRA columns.
#
# Does NOT use small_rira.rds — mocks RIRA hierarchy onto PBMC3k (or the human
# subset from template/gw/fetch_example_data.sh) so CiLISI / CELLTYPE_ASW paths
# match production inference (RIRA_Immune.cellclass → child column).
#
# Run from repo root:
#   Rscript scripts/ci/create_batch_effect_smoke_rds.R

out <- 'test-data/batch_effect_assessments/SMOKE.rds'
dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)

if (!requireNamespace('Seurat', quietly = TRUE)) {
    stop('Install Seurat to generate smoke RDS: install.packages("Seurat")')
}

repo_root <- Sys.getenv('GW_REPO_ROOT', unset = NA_character_)
if (!nzchar(repo_root)) {
    repo_root <- normalizePath(getwd(), wins = .Platform$OS.type == 'windows')
    if (basename(repo_root) == 'ci') {
        repo_root <- normalizePath(file.path(repo_root, '..', '..'))
    }
}

gw_human_rds <- file.path(repo_root, 'template', 'gw', 'data', 'pbmc3k_human.rds')

load_pbmc3k <- function() {
    if (file.exists(gw_human_rds)) {
        message('[SMOKE] Loading existing human subset: ', gw_human_rds)
        return(readRDS(gw_human_rds))
    }
    if (!requireNamespace('SeuratData', quietly = TRUE)) {
        stop('Install SeuratData or run template/gw/fetch_example_data.sh first')
    }
    suppressPackageStartupMessages(library(SeuratData))
    message('[SMOKE] Downloading pbmc3k via SeuratData (one-time)...')
    options(timeout = 300)
    InstallData('pbmc3k')
    data('pbmc3k', envir = environment())
    message('[SMOKE] Updating pbmc3k to current Seurat object format...')
    return(Seurat::UpdateSeuratObject(pbmc3k.final))
}

mock_rira_on_pbmc <- function(obj, n_batches = 3L, seed = 1L) {
    md_cols <- colnames(obj[[]])
    if (!'seurat_clusters' %in% md_cols) {
        obj <- Seurat::FindNeighbors(obj, verbose = FALSE)
        obj <- Seurat::FindClusters(obj, resolution = 0.5, verbose = FALSE)
    }
    cl <- as.character(obj[['seurat_clusters']])

    # Random experimental batches (n=3) — sufficient for LISI / CiLISI / ASW smoke tests.
    set.seed(seed)
    batch_names <- paste0('Batch', seq_len(n_batches))
    n_cells <- ncol(obj)
    min_per_batch <- 20L
    if (n_cells < min_per_batch * n_batches) {
        stop('Need at least ', min_per_batch * n_batches, ' cells for ', n_batches, ' batches; got ', n_cells)
    }
    repeat {
        obj$Batch <- sample(batch_names, n_cells, replace = TRUE)
        if (min(table(obj$Batch)) >= min_per_batch) break
    }

    # Mock RIRA hierarchy from PBMC3k cluster identity (not small_rira.rds).
    tnk_clusters <- c('0', '1', '2', '3', '5')
    myeloid_clusters <- c('4', '7', '8', '9')
    immune <- ifelse(cl %in% tnk_clusters, 'TNK',
        ifelse(cl %in% myeloid_clusters, 'Myeloid', 'TNK'))
    obj$RIRA_Immune.cellclass <- immune

    tnk_subtype <- rep(NA_character_, length(cl))
    tnk_subtype[cl %in% c('0', '1', '2')] <- 'CD4'
    tnk_subtype[cl %in% c('3', '5')] <- 'CD8'
    tnk_subtype[immune != 'TNK'] <- NA_character_
    obj$RIRA_TNK_v2.cellclass <- tnk_subtype

    myeloid_subtype <- rep(NA_character_, length(cl))
    myeloid_subtype[cl == '4'] <- 'Mono_FCGR3A'
    myeloid_subtype[cl == '7'] <- 'Mono_CD16'
    myeloid_subtype[cl == '8'] <- 'DC'
    myeloid_subtype[cl == '9'] <- 'Platelet'
    myeloid_subtype[immune != 'Myeloid'] <- NA_character_
    obj$RIRA_Myeloid_v3.cellclass <- myeloid_subtype

    obj
}

set.seed(1)
obj <- load_pbmc3k()

n_hvg <- 500L
if (nrow(obj) > n_hvg) {
    message('[SMOKE] Subsetting to top ', n_hvg, ' HVGs for fast smoke runs...')
    obj <- Seurat::FindVariableFeatures(obj, nfeatures = n_hvg, verbose = FALSE)
    obj <- obj[Seurat::VariableFeatures(obj), ]
}

obj <- mock_rira_on_pbmc(obj)

message('[SMOKE] Cells: ', ncol(obj),
        ' | batches (n=3, random): ', paste(names(table(obj$Batch)), collapse = ','),
        ' | min cells/batch: ', min(table(obj$Batch)))
print(table(obj$Batch))

obj <- Seurat::NormalizeData(obj, verbose = FALSE)
obj <- Seurat::FindVariableFeatures(obj, verbose = FALSE, nfeatures = min(200L, nrow(obj)))
obj <- Seurat::ScaleData(obj, verbose = FALSE)
obj <- Seurat::RunPCA(obj, verbose = FALSE)

saveRDS(obj, out)
message('Wrote ', out)
