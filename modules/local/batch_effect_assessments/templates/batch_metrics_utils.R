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
        # Fall back to finest available RIRA column with variation.
        for (col in rev(present)) {
            vals <- unique(as.character(md[[col]]))
            vals <- vals[!is.na(vals) & nzchar(vals)]
            if (length(vals) > 1L) return(col)
        }
        return(present[[length(present)]])
    }

    candidates[[1]]
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
