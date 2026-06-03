# Shared helpers for batch-effect assessment templates (rendered via Nextflow).

parse_methods <- function(raw) {
    methods <- trimws(strsplit(raw, ',')[[1]])
    methods <- methods[nzchar(methods)]
    toupper(methods)
}

method_enabled <- function(methods, token) {
    token <- toupper(token)
    token %in% toupper(methods)
}

STANDARD_RIRA <- c(
    'RIRA_Immune.cellclass',
    'RIRA_TNK_v2.cellclass',
    'RIRA_Myeloid_v3.cellclass'
)

default_parent_map <- function() {
    list(
        'RIRA_TNK_v2.cellclass'     = 'TNK',
        'RIRA_Myeloid_v3.cellclass' = 'Myeloid'
    )
}

normalize_immune_aliases <- function(obj) {
    md <- obj[[]]
    if ('RIRA_Immune_v2.cellclass' %in% colnames(md) &&
        !'RIRA_Immune.cellclass' %in% colnames(md)) {
        obj[[]][['RIRA_Immune.cellclass']] <- md[['RIRA_Immune_v2.cellclass']]
    }
    obj
}

infer_celltype_column <- function(obj, parent_col = 'RIRA_Immune.cellclass', parent_map = NULL) {
    if (is.null(parent_map) || length(parent_map) == 0) {
        parent_map <- default_parent_map()
    }
    md <- obj[[]]
    present <- intersect(STANDARD_RIRA, colnames(md))
    if (length(present) == 0) {
        return(NA_character_)
    }

    parent_col <- if (nzchar(parent_col) && parent_col %in% colnames(md)) {
        parent_col
    } else if ('RIRA_Immune.cellclass' %in% colnames(md)) {
        'RIRA_Immune.cellclass'
    } else {
        present[[1]]
    }

    parent_vals <- unique(as.character(md[[parent_col]]))
    parent_vals <- parent_vals[!is.na(parent_vals) & nzchar(parent_vals)]

    candidates <- character(0)
    for (col in present) {
        if (!col %in% names(parent_map)) next
        target <- parent_map[[col]]
        if (length(parent_vals) == 1L && identical(parent_vals[[1]], target)) {
            candidates <- c(candidates, col)
        }
    }

    if (length(candidates) == 0) {
        # Fall back to finest RIRA column with variation, but skip child columns
        # for lineages not present in the parent column (e.g. Myeloid on TNK-only).
        for (col in rev(present)) {
            if (col %in% names(parent_map) && length(parent_vals) > 0L) {
                if (!(parent_map[[col]] %in% parent_vals)) next
            }
            vals <- unique(as.character(md[[col]]))
            vals <- vals[!is.na(vals) & nzchar(vals)]
            if (length(vals) > 1L) return(col)
        }
        for (col in rev(present)) {
            if (col %in% names(parent_map) && length(parent_vals) > 0L) {
                if (!(parent_map[[col]] %in% parent_vals)) next
            }
            vals <- unique(as.character(md[[col]]))
            vals <- vals[!is.na(vals) & nzchar(vals)]
            if (length(vals) > 0L) return(col)
        }
        return(present[[length(present)]])
    }

    candidates[[1]]
}

run_ilisi <- function(emb, md, batch_col, perplexity = 30L) {
    res <- scIntegrationMetrics::compute_lisi(
        X = emb,
        meta_data = md,
        label_colnames = batch_col,
        perplexity = perplexity
    )
    as.numeric(res[[batch_col]])
}

run_cilisi <- function(emb, md, batch_col, celltype_col, perplexity = 30L) {
    split_res <- scIntegrationMetrics::compute_lisi_splitBy(
        X = emb,
        meta_data = md,
        label_colnames = batch_col,
        split_by_colname = celltype_col,
        normalize = TRUE,
        perplexity = perplexity
    )
    if (length(split_res) == 0) {
        return(numeric(0))
    }
    unlist(lapply(split_res, function(x) as.numeric(x[[batch_col]])))
}

run_batch_asw <- function(emb, md, batch_col) {
    res <- scIntegrationMetrics::compute_silhouette(
        X = emb,
        meta_data = md,
        label_colnames = batch_col
    )
    as.numeric(res[[batch_col]])
}

run_celltype_asw <- function(emb, md, celltype_col) {
    res <- scIntegrationMetrics::compute_silhouette(
        X = emb,
        meta_data = md,
        label_colnames = celltype_col
    )
    as.numeric(res[[celltype_col]])
}

discover_reductions <- function(obj, preferred = c('pca', 'harmony', 'scmodal', 'umap', 'tsne')) {
    avail <- names(obj@reductions)
    if (length(avail) == 0) return(character(0))
    ordered <- c(
        intersect(preferred, avail),
        setdiff(avail, preferred)
    )
    ordered
}

count_cells_per_batch <- function(obj, batch_col) {
    md <- obj[[]]
    if (!batch_col %in% colnames(md)) {
        stop('Batch column not found in meta.data: ', batch_col)
    }
    as.data.frame(table(md[[batch_col]]), stringsAsFactors = FALSE)
}

min_cells_per_batch <- function(obj, batch_col, min_n = 20L) {
    tab <- count_cells_per_batch(obj, batch_col)
    min(tab$Freq)
}

write_metric_status <- function(path, status, message = '') {
    df <- data.frame(status = status, message = message, stringsAsFactors = FALSE)
    write.csv(df, path, row.names = FALSE)
}

stratified_downsample <- function(emb, md, label_col, max_cells = 50000, seed = 42) {
    n_cells <- nrow(emb)
    if (n_cells <= max_cells) {
        return(list(emb = emb, md = md, n_kept = n_cells, n_dropped = 0L))
    }
    set.seed(seed)
    label_vals <- as.character(md[[label_col]])
    groups <- unique(label_vals)
    per_group <- ceiling(max_cells / length(groups))
    keep_idx <- unlist(lapply(groups, function(grp) {
        idx <- which(label_vals == grp)
        if (length(idx) <= per_group) idx else sample(idx, per_group)
    }))
    if (length(keep_idx) > max_cells) {
        keep_idx <- sort(sample(keep_idx, max_cells))
    }
    list(
        emb = emb[keep_idx, , drop = FALSE],
        md = md[keep_idx, , drop = FALSE],
        n_kept = length(keep_idx),
        n_dropped = n_cells - length(keep_idx)
    )
}
