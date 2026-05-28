#!/usr/bin/env Rscript
suppressPackageStartupMessages({
    library(jsonlite)
})

prep_path <- Sys.getenv('PREP_JSON')
ilisi_csv <- Sys.getenv('ILISI_CSV')
cilisi_csv <- Sys.getenv('CILISI_CSV')
asw_csv <- Sys.getenv('ASW_CSV')
kbet_csv <- Sys.getenv('KBET_CSV')
summary_out <- Sys.getenv('SUMMARY_CSV')
plot_out <- Sys.getenv('PLOT_PNG')
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

merged <- do.call(rbind, parts)
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
                title = paste0('iLISI — ', prep$sample_id, ' (', ilisi_row$reduction, ')'),
                y = 'LISI score',
                x = ''
            ) +
            ggplot2::theme_minimal()
        ggplot2::ggsave(plot_out, p, width = 6, height = 4, dpi = 150)
    }
}

if (nzchar(run_summary_out) && file.exists(run_summary_out)) {
    existing <- read.csv(run_summary_out, stringsAsFactors = FALSE)
    combined <- rbind(existing, merged)
    write.csv(combined, run_summary_out, row.names = FALSE)
} else if (nzchar(run_summary_out)) {
    write.csv(merged, run_summary_out, row.names = FALSE)
}
