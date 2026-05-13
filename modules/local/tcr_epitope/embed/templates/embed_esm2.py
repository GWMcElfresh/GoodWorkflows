#!/usr/bin/env python3
# NUMBA_DISABLE_JIT=1
"""
Nextflow template: embed_esm2.py
EMBED_CLONES — ESM-2 embeddings for TCR CDR3 sequences.

Loads ESM-2 (facebook/esm2_t6_8M_UR50D) from HuggingFace, embeds all unique
TCR clones (deduplicated by TRA+TRB CDR3 combo), and outputs a parquet with
clone_id + 320-dimensional embedding vector.

Also embeds epitope sequences from the input FASTA to support epitope-specific
binding prediction downstream.
"""

import logging
from pathlib import Path

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
logger = logging.getLogger("embed_esm2")

import torch
from transformers import AutoModel, AutoTokenizer
import pandas as pd
import numpy as np

# ── Parameters ──────────────────────────────────────────────────────────────
model_name = "${params.esm2_model_name}"
outdir = Path("${params.outdir}/tcr_epitope").resolve()
outdir.mkdir(parents=True, exist_ok=True)

tcr_csv = Path("${tcr_metadata_csv}").resolve()
epitope_fasta = Path("${epitope_fasta}").resolve()

logger.info("Loading ESM-2 model: %s", model_name)
logger.info("TCR metadata CSV: %s", tcr_csv)
logger.info("Epitope FASTA: %s", epitope_fasta)

tokenizer = AutoTokenizer.from_pretrained(model_name)
model = AutoModel.from_pretrained(model_name)
model.eval()

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
model = model.to(device)
logger.info("ESM-2 loaded. Device: %s", device)

# ── Load & deduplicate TCR clones ─────────────────────────────────────────────
logger.info("Loading TCR metadata from: %s", tcr_csv)
df = pd.read_csv(tcr_csv)
logger.info("Loaded %d cell-level TCR records", len(df))

# Identify TRA and TRB CDR3 columns
tra_col = "TRA" if "TRA" in df.columns else None
trb_col = "TRB" if "TRB" in df.columns else None

if tra_col is None and trb_col is None:
    raise ValueError(
        f"TCR metadata must have 'TRA' and/or 'TRB' columns. "
        f"Found columns: {list(df.columns)}"
    )

# Build clone_id = TRA_TRB combo; deduplicate
clone_records = []
for _, row in df.iterrows():
    tra = str(row.get(tra_col, "")) if tra_col else ""
    trb = str(row.get(trb_col, "")) if trb_col else ""
    # Skip rows where both TRA and TRB are empty/missing
    if not tra and not trb:
        continue
    clone_records.append({"TRA": tra, "TRB": trb})

clone_df = pd.DataFrame(clone_records)

# Deduplicate by TRA+TRB combo, keeping first occurrence
clone_df = clone_df.drop_duplicates(subset=["TRA", "TRB"], keep="first")
clone_df = clone_df.reset_index(drop=True)
clone_df["clone_id"] = clone_df.index.astype(str)
logger.info("Unique TCR clones (after dedup): %d", len(clone_df))

if len(clone_df) == 0:
    raise ValueError("No valid TCR clones found in metadata CSV.")

# ── ESM-2 embedding helper ────────────────────────────────────────────────────
def embed_sequence(seq: str) -> np.ndarray:
    """Mean-pool last_hidden_state[:,1:-1,:] for a single sequence."""
    if not seq or seq == "NA" or seq == "None":
        seq = "X"  # placeholder for missing sequence
    inputs = tokenizer(seq, return_tensors="pt", padding=True,
                       truncation=True, max_length=128)
    inputs = {k: v.to(device) for k, v in inputs.items()}
    with torch.no_grad():
        outputs = model(**inputs)
    # Mean-pool over token dimension (skip <cls> and <eos>)
    hidden = outputs.last_hidden_state  # (1, seq_len, 320)
    pooled = hidden[:, 1:-1, :].mean(dim=1)  # (1, 320)
    return pooled.cpu().numpy().squeeze()

# ── Embed all TCR clones ──────────────────────────────────────────────────────
logger.info("Embedding %d TCR clones …", len(clone_df))
tcr_emb_list = []
for idx, row in clone_df.iterrows():
    tra_emb = embed_sequence(row["TRA"])
    trb_emb = embed_sequence(row["TRB"])
    # Concatenate TRA + TRB = 640-dim, then take the full vector
    # For simplicity, embed as combined sequence if both present
    if row["TRA"] and row["TRB"]:
        combined = row["TRA"] + ":" + row["TRB"]
        emb = embed_sequence(combined)
    else:
        emb = tra_emb if row["TRA"] else trb_emb
    tcr_emb_list.append(emb)

tcr_emb_array = np.stack(tcr_emb_list)  # (n_clones, 320)
logger.info("TCR embedding matrix shape: %s", tcr_emb_array.shape)

# ── Embed epitope sequences from FASTA ───────────────────────────────────────
logger.info("Embedding epitope sequences from: %s", epitope_fasta)
epitope_records = {}
current_header = None
current_seq = []

with open(epitope_fasta, "r") as f:
    for line in f:
        line = line.strip()
        if line.startswith(">"):
            if current_header is not None and current_seq:
                epitope_records[current_header] = "".join(current_seq)
            current_header = line.lstrip(">").split()[0]
            current_seq = []
        else:
            current_seq.append(line)
    if current_header is not None and current_seq:
        epitope_records[current_header] = "".join(current_seq)

logger.info("Found %d epitopes in FASTA", len(epitope_records))

epitope_embs = {}
for epitope_id, seq in epitope_records.items():
    logger.info("  Embedding epitope: %s (len=%d)", epitope_id, len(seq))
    epitope_embs[epitope_id] = embed_sequence(seq)

# Save epitope embeddings as a side-channel (parquet)
epitope_emb_df = pd.DataFrame.from_dict(epitope_embs, orient="index")
epitope_emb_df.columns = [f"epitope_emb_{i}" for i in range(epitope_emb_df.shape[1])]
epitope_emb_df.index.name = "epitope_id"
epitope_emb_df.reset_index().to_parquet(outdir / "epitope_embeddings.parquet", index=False)
logger.info("Epitope embeddings saved to: %s", outdir / "epitope_embeddings.parquet")

# ── Build output dataframe ─────────────────────────────────────────────────────
clone_emb_df = clone_df[["clone_id"]].copy()
for i in range(tcr_emb_array.shape[1]):
    clone_emb_df[f"embedding_{i}"] = tcr_emb_array[:, i]

# Attach binding_score column from merged TCR metadata for traceability
# clone_id here maps to row index in clone_df
logger.info("Writing clone_embeddings.parquet …")
clone_emb_df.to_parquet(outdir / "clone_embeddings.parquet", index=False)
logger.info("Done. Outputs in: %s", outdir)