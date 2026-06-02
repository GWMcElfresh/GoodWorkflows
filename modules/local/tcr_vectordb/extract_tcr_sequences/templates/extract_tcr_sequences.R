#!/usr/bin/env Rscript
#
# Nextflow template: extract_tcr_sequences.R
#
# EXTRACT_TCR_SEQUENCES — convert Seurat meta.data into a long CSV of
# (cDNA_ID, SubjectId, barcode, chain, sequence, sequence_index, v_gene, j_gene)
# rows. This is the input for the ESM-2 embedding stage.
#
# Nextflow substitutions:
#   ${meta.id}  — sample identifier
#   ${rds}      — staged Seurat RDS path

options(warn = 2)

suppressPackageStartupMessages({
    library(Seurat)
})

sample_id <- "${meta.id}"
rds_path  <- "${rds}"
out_csv   <- paste0(sample_id, "_tcr_sequences.csv")

message("[EXTRACT_TCR_SEQUENCES] sample_id: ", sample_id)
message("[EXTRACT_TCR_SEQUENCES] rds_path : ", rds_path)
message("[EXTRACT_TCR_SEQUENCES] out_csv  : ", out_csv)

seurat_obj <- readRDS(rds_path)
if (!inherits(seurat_obj, "Seurat")) {
    stop("[EXTRACT_TCR_SEQUENCES] Loaded object is not a Seurat instance for sample: ", sample_id)
}

df <- seurat_obj@meta.data
df[["barcode"]] <- rownames(df)

required_cols <- c("cDNA_ID", "SubjectId")
missing_required <- setdiff(required_cols, colnames(df))
if (length(missing_required) > 0) {
    stop("[EXTRACT_TCR_SEQUENCES] Missing required metadata columns: ",
         paste(missing_required, collapse = ", "))
}

chain_cols <- c("TRA", "TRB")
missing_chains <- setdiff(chain_cols, colnames(df))
if (length(missing_chains) > 0) {
    # Optional Rdiscvr-based rescue: only run when LabKey settings exist.
    labkey_base <- Sys.getenv("LABKEY_BASE_URL", unset = "${params.labkey_base_url}")
    labkey_folder <- Sys.getenv("LABKEY_FOLDER", unset = "${params.labkey_folder}")
    if (!nzchar(labkey_base) || !nzchar(labkey_folder)) {
        stop("[EXTRACT_TCR_SEQUENCES] Missing TRA/TRB columns and no LabKey config available to attempt recovery. Missing: ",
             paste(missing_chains, collapse = ", "))
    }

    if (!requireNamespace("Rdiscvr", quietly = TRUE)) {
        stop("[EXTRACT_TCR_SEQUENCES] Missing TRA/TRB columns and Rdiscvr rescue requested, but Rdiscvr is not available.")
    }

    suppressPackageStartupMessages({
        library(Rdiscvr)
    })

    message("[EXTRACT_TCR_SEQUENCES] TRA/TRB missing; attempting Rdiscvr DownloadAndAppendTcrClonotypes (allowMissing=TRUE) ...")
    Rdiscvr::SetLabKeyDefaults(baseUrl = labkey_base, defaultFolder = labkey_folder)
    seurat_obj <- Rdiscvr::DownloadAndAppendTcrClonotypes(
        seuratObj = seurat_obj,
        outPath = tempdir(),
        dropExisting = TRUE,
        overwriteTcrTable = FALSE,
        allowMissing = TRUE,
        dropConflictingVJSegments = TRUE
    )

    df <- seurat_obj@meta.data
    df[["barcode"]] <- rownames(df)
    missing_chains <- setdiff(chain_cols, colnames(df))
    if (length(missing_chains) > 0) {
        stop("[EXTRACT_TCR_SEQUENCES] After Rdiscvr recovery, still missing TRA/TRB columns: ",
             paste(missing_chains, collapse = ", "))
    }
}

# Optional V/J columns for conflicting V/J filtering.
gene_cols <- c("TRA_V", "TRA_J", "TRB_V", "TRB_J")
for (gc in gene_cols) {
    if (!gc %in% colnames(df)) {
        df[[gc]] <- NA_character_
    }
}

clean_field <- function(x) {
    if (is.na(x)) return("")
    x <- as.character(x)
    x <- trimws(x)
    if (!nzchar(x)) return("")
    if (x %in% c("NA", "None", "null", "NULL")) return("")
    return(x)
}

split_aligned <- function(seq_str, gene_str) {
    # Split comma-separated sequences and (optionally) comma-separated genes.
    # If gene count doesn't match sequence count, replicate the first gene value.
    seq_str <- clean_field(seq_str)
    gene_str <- clean_field(gene_str)

    if (!nzchar(seq_str)) return(list(seqs = character(0), genes = character(0)))

    seqs <- strsplit(seq_str, ",", fixed = TRUE)[[1]]
    seqs <- trimws(seqs)
    seqs <- seqs[nzchar(seqs)]
    if (length(seqs) == 0) return(list(seqs = character(0), genes = character(0)))

    if (!nzchar(gene_str)) {
        genes <- rep(NA_character_, length(seqs))
        return(list(seqs = seqs, genes = genes))
    }

    genes <- strsplit(gene_str, ",", fixed = TRUE)[[1]]
    genes <- trimws(genes)
    genes <- genes[nzchar(genes)]

    if (length(genes) == length(seqs)) {
        return(list(seqs = seqs, genes = genes))
    }

    if (length(genes) == 0) {
        genes <- rep(NA_character_, length(seqs))
        return(list(seqs = seqs, genes = genes))
    }

    genes <- rep(genes[[1]], length(seqs))
    return(list(seqs = seqs, genes = genes))
}

out_rows <- list()
k <- 0

for (i in seq_len(nrow(df))) {
    cDNA_ID   <- clean_field(df[["cDNA_ID"]][[i]])
    SubjectId <- clean_field(df[["SubjectId"]][[i]])
    barcode   <- clean_field(df[["barcode"]][[i]])

    # Skip empty ids: prevents malformed downstream joins.
    if (!nzchar(cDNA_ID) || !nzchar(SubjectId) || !nzchar(barcode)) next

    # TRA
    tra_split_v <- split_aligned(df[["TRA"]][[i]], df[["TRA_V"]][[i]])
    tra_split_j <- split_aligned(df[["TRA"]][[i]], df[["TRA_J"]][[i]])
    tra_seqs <- tra_split_v[["seqs"]]
    if (length(tra_seqs) > 0) {
        for (seq_i in seq_along(tra_seqs)) {
            k <- k + 1
            out_rows[[k]] <- data.frame(
                cDNA_ID = cDNA_ID,
                SubjectId = SubjectId,
                barcode = barcode,
                chain = "TRA",
                sequence = tra_seqs[[seq_i]],
                sequence_index = as.integer(seq_i - 1),  # 0-based index
                v_gene = tra_split_v[["genes"]][[seq_i]],
                j_gene = tra_split_j[["genes"]][[seq_i]],
                stringsAsFactors = FALSE
            )
        }
    }

    # TRB
    trb_split_v <- split_aligned(df[["TRB"]][[i]], df[["TRB_V"]][[i]])
    trb_split_j <- split_aligned(df[["TRB"]][[i]], df[["TRB_J"]][[i]])
    trb_seqs <- trb_split_v[["seqs"]]
    if (length(trb_seqs) > 0) {
        for (seq_i in seq_along(trb_seqs)) {
            k <- k + 1
            out_rows[[k]] <- data.frame(
                cDNA_ID = cDNA_ID,
                SubjectId = SubjectId,
                barcode = barcode,
                chain = "TRB",
                sequence = trb_seqs[[seq_i]],
                sequence_index = as.integer(seq_i - 1),  # 0-based index
                v_gene = trb_split_v[["genes"]][[seq_i]],
                j_gene = trb_split_j[["genes"]][[seq_i]],
                stringsAsFactors = FALSE
            )
        }
    }
}

if (length(out_rows) == 0) {
    message("[EXTRACT_TCR_SEQUENCES] No sequences found; writing empty CSV with headers.")
    empty_df <- data.frame(
        cDNA_ID = character(0),
        SubjectId = character(0),
        barcode = character(0),
        chain = character(0),
        sequence = character(0),
        sequence_index = integer(0),
        v_gene = character(0),
        j_gene = character(0),
        stringsAsFactors = FALSE
    )
    utils::write.csv(empty_df, file = out_csv, row.names = FALSE)
} else {
    out_df <- do.call(rbind, out_rows)
    utils::write.csv(out_df, file = out_csv, row.names = FALSE)
}

message("[EXTRACT_TCR_SEQUENCES] Wrote: ", out_csv)

