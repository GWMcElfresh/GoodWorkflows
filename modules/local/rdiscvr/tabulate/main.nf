/*
 * Process: TABULATE
 *
 * Builds a wide, subject-level table from per-sample Seurat metadata CSV files.
 *
 * Standard RIRA cell-type columns (RIRA_Immune.cellclass, RIRA_TNK_v2.cellclass,
 * RIRA_Myeloid_v3.cellclass) are always processed when present.  Any additional
 * columns named in tabulate_celltype_cols are processed on top of those.
 *
 * tabulate_parent_col / tabulate_celltype_parent_map define optional hierarchy
 * filters: a child column is computed only over rows where the parent column
 * equals the mapped value (e.g. RIRA_TNK_v2.cellclass is computed only over
 * cells whose RIRA_Immune.cellclass == "TNK").
 *
 * For every cell-type column the module produces:
 *   - Fraction_<level>    : proportion of cells in that group relative to the
 *                           denominator (parent-filtered total for child cols,
 *                           global total for RIRA_Immune.cellclass)
 *   - Count_<level>       : raw barcode count
 *   - Total_<col>_Cells   : total denominator for that column (per cDNA_ID)
 *
 * Additionally, because a single cDNA_ID may appear in several cohort files
 * (TNK, Myeloid, BCells ...),  the module de-duplicates barcodes across files
 * before computing the grand Total_Cells column.
 *
 * The final CSV has one row per cDNA_ID.
 */

process TABULATE {
    tag "subjectIdTable"
    label 'process_tabulate'

    container 'ghcr.io/bimberlabinternal/rdiscvr:latest'

    publishDir "${params.outdir}/tabulate", mode: 'copy'

    input:
    path(metadata_csvs)
    val(tabulate_id_cols)
    val(tabulate_celltype_cols)
    val(tabulate_parent_col)
    val(tabulate_celltype_parent_map)

    output:
    path('subjectIdTable.csv'), emit: subject_table

    stub:
    """
    printf 'cDNA_ID\n' > subjectIdTable.csv
    """

    script:
    """
    #!/usr/bin/env Rscript
    options(warn = 2)

    suppressWarnings(suppressPackageStartupMessages({
        library(dplyr)
        library(tidyr)
        library(purrr)
        library(stringr)
        library(readr)
    }))

    # ---------------------------------------------------------------------------
    # Helpers
    # ---------------------------------------------------------------------------

    parse_csv_list <- function(x) {
        items <- strsplit(as.character(x), ',', fixed = TRUE)[[1]]
        items <- trimws(items)
        items[nzchar(items)]
    }

    parse_parent_map <- function(map_str) {
        out <- list()
        if (!nzchar(trimws(map_str))) return(out)
        entries <- strsplit(map_str, ',', fixed = TRUE)[[1]]
        for (entry in entries) {
            entry <- trimws(entry)
            if (!nzchar(entry)) next
            kv <- strsplit(entry, ':', fixed = TRUE)[[1]]
            if (length(kv) != 2)
                stop('Invalid tabulate_celltype_parent_map entry: ', entry,
                     '. Expected format celltype_col:parentValue')
            key   <- trimws(kv[[1]])
            value <- trimws(kv[[2]])
            if (!nzchar(key) || !nzchar(value))
                stop('Empty key or value in tabulate_celltype_parent_map entry: ', entry)
            out[[key]] <- value
        }
        out
    }

    sanitize_col <- function(x) {
        # Turns arbitrary cell-type level strings into safe column-name fragments.
        x <- as.character(x)
        x <- ifelse(is.na(x) | !nzchar(x), 'NA', x)
        x <- gsub('[^A-Za-z0-9_]+', '_', x)
        x <- gsub('_+', '_', x)
        x <- gsub('^_|_\$', '', x)
        ifelse(nzchar(x), x, 'NA')
    }

    normalize_immune_class <- function(x) {
        x <- as.character(x)
        dplyr::case_when(
            x == 'T_NK' ~ 'TNK',
            TRUE ~ x
        )
    }

    # ---------------------------------------------------------------------------
    # Read and bind all staged per-sample metadata CSVs.
    # The first column written by write.csv(..., row.names=TRUE) is the barcode.
    # We keep it as 'barcode' for deduplication across cohort files.
    # ---------------------------------------------------------------------------

    metadata_paths <- list.files('.', pattern = '_metadata\\\\.csv\$', full.names = TRUE)
    if (length(metadata_paths) == 0)
        stop('No *_metadata.csv files were staged for tabulation.')

    message('[TABULATE] Found ', length(metadata_paths), ' metadata file(s):')
    for (p in metadata_paths) message('  ', p)

    read_meta <- function(path) {
        # vroom emits a vroom_parse_issue warning for ambiguous column types
        # (common in wide single-cell metadata CSVs).  Muffle that specific
        # warning class so it does not get converted to an error by warn=2.
        df <- withCallingHandlers(
            readr::read_csv(path, show_col_types = FALSE),
            vroom_parse_issue = function(w) {
                message('[TABULATE] Parse note in ', basename(path), ': ', conditionMessage(w))
                invokeRestart('muffleWarning')
            }
        )
        # If the CSV was written with row.names=TRUE the first col is barcodes but
        # has no header; readr names it '...1'.  Normalise to 'barcode'.
        if ('...1' %in% colnames(df)) {
            df <- dplyr::rename(df, barcode = `...1`)
        } else if ('cellbarcode' %in% colnames(df) && !'barcode' %in% colnames(df)) {
            df <- dplyr::rename(df, barcode = cellbarcode)
        } else if (!'barcode' %in% colnames(df)) {
            df[['barcode']] <- paste0('bc', seq_len(nrow(df)))
        }
        if ('RIRA_Immune_v2.cellclass' %in% colnames(df) &&
            !'RIRA_Immune.cellclass' %in% colnames(df)) {
            df[['RIRA_Immune.cellclass']] <- df[['RIRA_Immune_v2.cellclass']]
        }
        if ('RIRA_Immune.cellclass' %in% colnames(df)) {
            df[['RIRA_Immune.cellclass']] <- normalize_immune_class(df[['RIRA_Immune.cellclass']])
        }
        # Tag the source file so we can compute per-cohort totals later.
        df[['source_file']] <- basename(path)
        df
    }

    raw_list <- purrr::map(metadata_paths, read_meta)

    # ---------------------------------------------------------------------------
    # Resolve id_cols and required RIRA standard columns
    # ---------------------------------------------------------------------------

    id_cols    <- parse_csv_list('${tabulate_id_cols}')
    extra_cols <- parse_csv_list('${tabulate_celltype_cols}')
    parent_col <- trimws('${tabulate_parent_col}')
    parent_map <- parse_parent_map('${tabulate_celltype_parent_map}')

    if (!'cDNA_ID' %in% id_cols) id_cols <- c('cDNA_ID', id_cols)

    # Standard RIRA cell-type columns – always used when present.
    STANDARD_RIRA <- c('RIRA_Immune.cellclass', 'RIRA_TNK_v2.cellclass', 'RIRA_Myeloid_v3.cellclass')

    # Standard hard-wired parent map.  User-supplied entries extend / override it.
    default_parent_map <- list(
        'RIRA_TNK_v2.cellclass'     = 'TNK',
        'RIRA_Myeloid_v3.cellclass' = 'Myeloid'
    )
    parent_map <- c(default_parent_map, parent_map)   # user entries win on conflict

    # Default parent column is RIRA_Immune.cellclass if not set.
    if (!nzchar(parent_col)) parent_col <- 'RIRA_Immune.cellclass'

    # ---------------------------------------------------------------------------
    # Merge all cohort frames into one combined frame, keeping track of unique
    # barcodes per (cDNA_ID, source_file) for later total-cell bookkeeping.
    # ---------------------------------------------------------------------------

    all_cols_present <- purrr::reduce(purrr::map(raw_list, colnames), intersect)

    combined_df <- dplyr::bind_rows(raw_list)

    missing_id_cols <- setdiff(id_cols, colnames(combined_df))
    if (length(missing_id_cols) > 0) {
        message('[TABULATE] Skipping missing id columns: ', paste(missing_id_cols, collapse = ', '))
        id_cols <- intersect(id_cols, colnames(combined_df))
    }
    if (!'cDNA_ID' %in% id_cols) {
        stop('Metadata is missing required cDNA_ID column.')
    }

    # Fill id_cols within each cDNA_ID (they should be constant, but sparse in
    # some CSVs depending on how metadata was written).
    fill_these <- setdiff(id_cols, c('cDNA_ID', 'barcode', 'source_file'))
    if (length(fill_these) > 0) {
        combined_df <- combined_df %>%
            group_by(cDNA_ID) %>%
            tidyr::fill(all_of(fill_these), .direction = 'downup') %>%
            ungroup()
    }

    # Deduplicated id frame – one row per unique cDNA_ID combination of id cols.
    id_frame <- combined_df %>%
        dplyr::select(all_of(id_cols)) %>%
        dplyr::distinct()

    # Grand total unique barcodes per cDNA_ID (across all cohort files, deduped).
    grand_totals <- combined_df %>%
        dplyr::select(cDNA_ID, barcode) %>%
        dplyr::distinct() %>%
        dplyr::count(cDNA_ID, name = 'Total_Cells')

    # Per-source-file totals become Total_<tag>_Cells.  The tag is derived from
    # the file stem, e.g. "SAMPLE_01_metadata.csv" -> "SAMPLE_01" but because
    # multiple samples share a tag we instead use the RIRA_Immune.cellclass parent
    # values to name the per-group totals automatically (see below).

    # ---------------------------------------------------------------------------
    # Decide which cell-type columns to process.
    # Present RIRA standard cols always included; extra_cols appended if present.
    # ---------------------------------------------------------------------------

    present_rira <- intersect(STANDARD_RIRA, colnames(combined_df))
    all_celltype_cols <- unique(c(present_rira, extra_cols))
    all_celltype_cols <- all_celltype_cols[all_celltype_cols %in% colnames(combined_df)]

    if (length(all_celltype_cols) == 0)
        stop('No cell-type columns found in metadata. Expected at least one of: ',
             paste(STANDARD_RIRA, collapse = ', '))

    message('[TABULATE] Cell-type columns to tabulate: ', paste(all_celltype_cols, collapse = ', '))

    # ---------------------------------------------------------------------------
    # Core tabulation function
    #
    # Returns a wide data frame keyed on id_cols with columns:
    #   Fraction_<level>    fraction of cells (relative to denominator)
    #   Count_<level>       raw barcode count
    #   Total_<colTag>_Cells total denominator (per cDNA_ID)
    # ---------------------------------------------------------------------------

    compute_wide <- function(df, id_cols, celltype_col, parent_col, parent_map, id_frame) {
        work_df <- df

        # Apply parent filter if this col has a parent mapping.
        if (celltype_col %in% names(parent_map)) {
            parent_value <- parent_map[[celltype_col]]
            if (nzchar(parent_col) && parent_col %in% colnames(work_df)) {
                work_df <- work_df %>% filter(.data[[parent_col]] == parent_value)
            }
        }

        # Drop rows with missing / empty cell-type labels.
        work_df <- work_df %>%
            filter(!is.na(.data[[celltype_col]]),
                   nzchar(trimws(as.character(.data[[celltype_col]]))))

        col_tag <- sanitize_col(celltype_col)   # e.g. "RIRA_TNK_v2_cellclass"

        if (nrow(work_df) == 0) {
            message('[TABULATE] No rows for ', celltype_col, ' after filtering – returning empty.')
            return(id_frame %>% mutate(!!paste0('Total_', col_tag, '_Cells') := 0L))
        }

        # Deduplicate barcodes within each id group before counting.
        work_df <- work_df %>%
            dplyr::distinct(across(all_of(c(id_cols, 'barcode', celltype_col))))

        totals <- work_df %>%
            dplyr::distinct(across(all_of(c(id_cols, 'barcode')))) %>%
            dplyr::count(across(all_of(id_cols)), name = paste0('Total_', col_tag, '_Cells'))

        counts <- work_df %>%
            dplyr::count(across(all_of(c(id_cols, celltype_col))), name = 'count')

        observed_levels <- sort(unique(as.character(work_df[[celltype_col]])))

        completed <- tidyr::crossing(id_frame,
                         !!!stats::setNames(list(observed_levels), celltype_col)) %>%
            left_join(counts, by = c(id_cols, celltype_col)) %>%
            left_join(totals, by = id_cols) %>%
            mutate(
                count = tidyr::replace_na(count, 0L),
                !!paste0('Total_', col_tag, '_Cells') :=
                    tidyr::replace_na(.data[[paste0('Total_', col_tag, '_Cells')]], 0L),
                Fraction = dplyr::if_else(
                    .data[[paste0('Total_', col_tag, '_Cells')]] > 0,
                    count / .data[[paste0('Total_', col_tag, '_Cells')]],
                    0
                ),
                level_safe = sanitize_col(.data[[celltype_col]])
            )

        # Pivot counts and fractions both into separate wide columns.
        wide_frac <- completed %>%
            dplyr::select(all_of(id_cols), level_safe, Fraction) %>%
            tidyr::pivot_wider(
                names_from   = level_safe,
                values_from  = Fraction,
                values_fill  = 0,
                names_prefix = paste0(col_tag, '_Fraction_')
            )

        wide_count <- completed %>%
            dplyr::select(all_of(id_cols), level_safe, count) %>%
            tidyr::pivot_wider(
                names_from   = level_safe,
                values_from  = count,
                values_fill  = 0L,
                names_prefix = paste0(col_tag, '_Count_')
            )

        wide_total <- totals   # already keyed on id_cols

        wide_df <- wide_frac %>%
            left_join(wide_count, by = id_cols) %>%
            left_join(wide_total, by = id_cols) %>%
            mutate(across(starts_with(paste0('Total_', col_tag)),
                          ~ tidyr::replace_na(., 0L)))

        wide_df
    }

    # ---------------------------------------------------------------------------
    # Run tabulation for every cell-type column and merge results
    # ---------------------------------------------------------------------------

    wide_tables <- purrr::map(
        all_celltype_cols,
        ~ compute_wide(
            df          = combined_df,
            id_cols     = id_cols,
            celltype_col = .x,
            parent_col  = parent_col,
            parent_map  = parent_map,
            id_frame    = id_frame
        )
    )

    subject_table <- purrr::reduce(
        wide_tables,
        ~ full_join(.x, .y, by = id_cols)
    ) %>%
        left_join(grand_totals, by = 'cDNA_ID') %>%
        dplyr::arrange(cDNA_ID)

    message('[TABULATE] Output: ', nrow(subject_table), ' rows, ',
            ncol(subject_table), ' columns')

    readr::write_csv(subject_table, 'subjectIdTable.csv')
    """
}
