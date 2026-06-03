#!/usr/bin/env Rscript
suppressPackageStartupMessages({
    library(jsonlite)
})

prep_path <- Sys.getenv('PREP_JSON')
ilisi_csv <- Sys.getenv('ILISI_CSV')
cilisi_csv <- Sys.getenv('CILISI_CSV')
asw_csv <- Sys.getenv('ASW_CSV')
kbet_csv <- Sys.getenv('KBET_CSV')
cilisi_cells_csv <- Sys.getenv('CILISI_CELLS_CSV', unset = NA_character_)
asw_cells_csv <- Sys.getenv('ASW_CELLS_CSV', unset = NA_character_)
summary_out <- Sys.getenv('SUMMARY_CSV')
plot_out <- Sys.getenv('PLOT_PNG')
celltype_plot_out <- Sys.getenv('CELLTYPE_PLOT_PNG', unset = NA_character_)
run_summary_out <- Sys.getenv('RUN_SUMMARY_CSV')

read_if <- function(path) {
    if (nzchar(path) && file.exists(path)) read.csv(path, stringsAsFactors = FALSE) else NULL
}

prep <- fromJSON(prep_path)
parts <- list(
    read_if(ilisi_csv),
    read_if(cilisi_csv),
    read_if(asw_csv),
    read_if(kbet_csv)
)
parts <- parts[!vapply(parts, is.null, logical(1))]

if (length(parts) == 0) {
    stop('No metric CSVs provided for collection')
}

merged <- tryCatch(
    do.call(rbind, parts),
    error = function(e) {
        all_cols <- unique(unlist(lapply(parts, colnames)))
        parts_padded <- lapply(parts, function(df) {
            for (col in setdiff(all_cols, colnames(df))) df[[col]] <- NA
            df[, all_cols]
        })
        do.call(rbind, parts_padded)
    }
)
merged$batch_column <- prep$batch_column
merged$methods_run <- paste(prep$methods, collapse = ',')
write.csv(merged, summary_out, row.names = FALSE)

# Simple columnar reference plot (good / bad / observed) for LISI when present.
if (requireNamespace('ggplot2', quietly = TRUE) && any(merged$metric == 'ilisi', na.rm = TRUE)) {
    ilisi_row <- merged[merged$metric == 'ilisi', , drop = FALSE][1, , drop = FALSE]
    if (!is.na(ilisi_row$ilisi_median)) {
        df <- data.frame(
            label = c('poor_mixing', 'good_mixing', 'observed'),
            value = c(1, prep$n_batches, ilisi_row$ilisi_median),
            stringsAsFactors = FALSE
        )
        p <- ggplot2::ggplot(df, ggplot2::aes(x = label, y = value)) +
            ggplot2::geom_col(fill = 'steelblue') +
            ggplot2::labs(
                title = paste0('iLISI -- ', prep$sample_id, ' (', ilisi_row$reduction, ')'),
                y = 'LISI score',
                x = ''
            ) +
            ggplot2::theme_minimal()
        ggplot2::ggsave(plot_out, p, width = 6, height = 4, dpi = 150)
    }
}

# ---- Stacked histogram visualization for per-cell metrics ----
cilisi_cells <- if (!is.na(cilisi_cells_csv) && nzchar(cilisi_cells_csv)) read_if(cilisi_cells_csv) else NULL
asw_cells <- if (!is.na(asw_cells_csv) && nzchar(asw_cells_csv)) read_if(asw_cells_csv) else NULL

has_any_cells <- (!is.null(cilisi_cells) && nrow(cilisi_cells) > 0) ||
                 (!is.null(asw_cells) && nrow(asw_cells) > 0)

if (has_any_cells && !is.na(celltype_plot_out) && nzchar(celltype_plot_out) &&
    requireNamespace('ggplot2', quietly = TRUE)) {

    has_patchwork <- requireNamespace('patchwork', quietly = TRUE)

    plot_list <- list()

    # --- Panel 1: CiLISI per-cell distribution ---
    if (!is.null(cilisi_cells) && nrow(cilisi_cells) > 0) {
        cilisi_median <- median(cilisi_cells$cilisi_value, na.rm = TRUE)
        cilisi_max <- max(cilisi_cells$cilisi_value, na.rm = TRUE)
        cilisi_df <- cilisi_cells

        p_cilisi <- ggplot2::ggplot(cilisi_df, ggplot2::aes(x = cilisi_value)) +
            ggplot2::geom_rect(
                data = data.frame(
                    xmin = c(-Inf, 1, 1.5),
                    xmax = c(1, 1.5, Inf),
                    fill = c('poor', 'fair', 'good'),
                    stringsAsFactors = FALSE
                ),
                ggplot2::aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf, fill = fill),
                alpha = 0.15, inherit.aes = FALSE
            ) +
            ggplot2::scale_fill_manual(
                values = c(poor = '#d73027', fair = '#fee08b', good = '#1a9850'),
                guide = 'none'
            ) +
            ggplot2::geom_histogram(bins = 50, fill = 'gray30', alpha = 0.7) +
            ggplot2::geom_vline(xintercept = cilisi_median, linetype = 'dashed', linewidth = 0.6) +
            ggplot2::annotate('text', x = cilisi_median, y = Inf,
                              label = sprintf(' median: %.2f', cilisi_median),
                              hjust = -0.1, vjust = 1.5, size = 3) +
            ggplot2::labs(
                title = 'CiLISI Distribution',
                subtitle = 'Poor (< 1.5)  |  Fair (1.0-1.5)  |  Good (> 1.5)',
                x = 'CiLISI score', y = 'Cells'
            ) +
            ggplot2::theme_minimal() +
            ggplot2::theme(plot.title = ggplot2::element_text(face = 'bold'))
    } else {
        p_cilisi <- NULL
    }

    # --- Panel 2: Batch ASW mixing score ---
    if (!is.null(asw_cells) && nrow(asw_cells) > 0 &&
        'batch_asw' %in% colnames(asw_cells) &&
        !all(is.na(asw_cells$batch_asw))) {

        asw_cells$mixing_score <- 1 - asw_cells$batch_asw
        mixing_mean <- mean(asw_cells$mixing_score, na.rm = TRUE)
        mixing_max <- max(asw_cells$mixing_score, na.rm = TRUE)

        p_asw_batch <- ggplot2::ggplot(asw_cells, ggplot2::aes(x = mixing_score)) +
            ggplot2::geom_rect(
                data = data.frame(
                    xmin = c(-Inf, 0.5),
                    xmax = c(0.5, Inf),
                    fill = c('poor', 'good'),
                    stringsAsFactors = FALSE
                ),
                ggplot2::aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf, fill = fill),
                alpha = 0.15, inherit.aes = FALSE
            ) +
            ggplot2::scale_fill_manual(
                values = c(poor = '#d73027', good = '#1a9850'),
                guide = 'none'
            ) +
            ggplot2::geom_histogram(bins = 50, fill = 'gray30', alpha = 0.7) +
            ggplot2::geom_vline(xintercept = mixing_mean, linetype = 'dashed', linewidth = 0.6) +
            ggplot2::annotate('text', x = mixing_mean, y = Inf,
                              label = sprintf(' mean: %.2f', mixing_mean),
                              hjust = -0.1, vjust = 1.5, size = 3) +
            ggplot2::labs(
                title = 'Batch ASW Mixing Score (1 - batch ASW)',
                subtitle = 'Poor (< 0.5)  |  Good (> 0.5)',
                x = 'Mixing score', y = 'Cells'
            ) +
            ggplot2::theme_minimal() +
            ggplot2::theme(plot.title = ggplot2::element_text(face = 'bold'))
    } else {
        p_asw_batch <- NULL
    }

    # --- Panel 3: Celltype ASW ---
    if (!is.null(asw_cells) && nrow(asw_cells) > 0 &&
        'celltype_asw' %in% colnames(asw_cells) &&
        !all(is.na(asw_cells$celltype_asw))) {

        ct_asw_mean <- mean(asw_cells$celltype_asw, na.rm = TRUE)

        p_asw_ct <- ggplot2::ggplot(asw_cells, ggplot2::aes(x = celltype_asw)) +
            ggplot2::geom_rect(
                data = data.frame(
                    xmin = c(-Inf, 0, 0.2),
                    xmax = c(0, 0.2, Inf),
                    fill = c('poor', 'fair', 'good'),
                    stringsAsFactors = FALSE
                ),
                ggplot2::aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf, fill = fill),
                alpha = 0.15, inherit.aes = FALSE
            ) +
            ggplot2::scale_fill_manual(
                values = c(poor = '#d73027', fair = '#fee08b', good = '#1a9850'),
                guide = 'none'
            ) +
            ggplot2::geom_histogram(bins = 50, fill = 'gray30', alpha = 0.7) +
            ggplot2::geom_vline(xintercept = ct_asw_mean, linetype = 'dashed', linewidth = 0.6) +
            ggplot2::annotate('text', x = ct_asw_mean, y = Inf,
                              label = sprintf(' mean: %.2f', ct_asw_mean),
                              hjust = -0.1, vjust = 1.5, size = 3) +
            ggplot2::labs(
                title = 'Celltype ASW',
                subtitle = 'Disrupted (< 0)  |  Neutral (0-0.2)  |  Preserved (> 0.2)',
                x = 'Silhouette width', y = 'Cells'
            ) +
            ggplot2::theme_minimal() +
            ggplot2::theme(plot.title = ggplot2::element_text(face = 'bold'))
    } else {
        p_asw_ct <- NULL
    }

    # Collect non-null panels
    non_null <- list()
    if (!is.null(p_cilisi)) non_null <- c(non_null, list(p_cilisi))
    if (!is.null(p_asw_batch)) non_null <- c(non_null, list(p_asw_batch))
    if (!is.null(p_asw_ct)) non_null <- c(non_null, list(p_asw_ct))

    if (length(non_null) > 0) {
        if (has_patchwork && length(non_null) > 1) {
            combined_plot <- patchwork::wrap_plots(non_null, ncol = 1)
        } else if (length(non_null) == 1) {
            combined_plot <- non_null[[1]]
        } else {
            combined_plot <- non_null[[1]]
        }
        sample_label <- prep$sample_id
        red_label <- prep$reduction %||% ''
        combined_plot <- combined_plot +
            ggplot2::plot_annotation(
                title = paste0('Cell-type Assessment -- ', sample_label, ' (', ilisi_row$reduction %||% red_label, ')'),
                theme = ggplot2::theme(plot.title = ggplot2::element_text(face = 'bold', hjust = 0.5))
            )
        ggplot2::ggsave(celltype_plot_out, combined_plot, width = 7, height = 3 * length(non_null), dpi = 150)
    }
}

if (nzchar(run_summary_out) && file.exists(run_summary_out)) {
    existing <- read.csv(run_summary_out, stringsAsFactors = FALSE)
    combined <- rbind(existing, merged)
    write.csv(combined, run_summary_out, row.names = FALSE)
} else if (nzchar(run_summary_out)) {
    write.csv(merged, run_summary_out, row.names = FALSE)
}
