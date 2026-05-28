#!/usr/bin/env Rscript
# Create a tiny Seurat object for batch_effect_assessments stub/smoke tests.
# Run locally: Rscript scripts/ci/create_batch_effect_smoke_rds.R

out <- 'test-data/batch_effect_assessments/SMOKE.rds'
dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)

if (!requireNamespace('Seurat', quietly = TRUE)) {
    stop('Install Seurat to generate smoke RDS: install.packages("Seurat")')
}

set.seed(1)
n <- 80
batch <- rep(c('B1', 'B2'), each = n / 2)
mat <- matrix(rpois(200 * n, lambda = 2), nrow = 200)
rownames(mat) <- paste0('GENE', seq_len(200))
colnames(mat) <- paste0('CELL', seq_len(n))

obj <- Seurat::CreateSeuratObject(counts = mat, meta.data = data.frame(
    Batch = batch,
    RIRA_Immune.cellclass = rep(c('TNK', 'TNK'), each = n / 2),
    RIRA_TNK_v2.cellclass = sample(c('CD4', 'CD8'), n, replace = TRUE),
    stringsAsFactors = FALSE
))
obj <- Seurat::RunPCA(obj, verbose = FALSE)
saveRDS(obj, out)
message('Wrote ', out)
