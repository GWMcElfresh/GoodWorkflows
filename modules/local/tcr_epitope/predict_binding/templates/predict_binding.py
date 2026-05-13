#!/usr/bin/env python3
# NUMBA_DISABLE_JIT=1
"""
Nextflow template: predict_binding.py
PREDICT_BINDING — XGBoost clone × peptide binding score prediction.

For each TCR clone (from EMBED_CLONES) and each peptide in the sample's epitope pool:
  1. Embed epitope sequence using ESM-2 (loaded once, cached)
  2. Concatenate epitope ESM-2 embedding (tcr_embedding_dim) + TCR clone embedding
     → 2 × tcr_embedding_dim feature vector
  3. Apply pre-fitted StandardScaler
  4. Predict binding_score = model.predict_proba(X_scaled)[:, 1]

Outputs:
  - clone × peptide probability matrix (parquet)
  - cell-level expansion (one row per cell, scores assigned via clonotype_id join)
"""

import os
# NUMBA_DISABLE_JIT=1 must be at very top (before any import)
# injected by Nextflow via template directive; placed first for safety

import logging
from pathlib import Path

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
logger = logging.getLogger("predict_binding")

import pandas as pd
import numpy as np
import pickle

# ── Parameters ────────────────────────────────────────────────────────────────
meta_id = "${meta.id}"
clone_emb_parquet = Path("${clone_embeddings_parquet}").resolve()
epitope_fasta = Path("${epitope_fasta}").resolve()
binding_model_dir = Path("${binding_model_dir}").resolve()
outdir = Path("${params.outdir}/tcr_epitope").resolve()
outdir.mkdir(parents=True, exist_ok=True)

esm2_model = "${params.esm2_model_name}"
tcr_emb_dim = int("${params.tcr_embedding_dim}")

logger.info("Sample: %s", meta_id)
logger.info("Clone embeddings: %s", clone_emb_parquet)
logger.info("Epitope FASTA: %s", epitope_fasta)
logger.info("Binding model dir: %s", binding_model_dir)

# ── Load clone embeddings ────────────────────────────────────────────────────
logger.info("Loading clone embeddings …")
clone_emb_df = pd.read_parquet(clone_emb_parquet)
logger.info("Clone embeddings shape: %s", clone_emb_df.shape)

# Separate clone_id and embedding columns
clone_ids = clone_emb_df["clone_id"].values
emb_cols = [c for c in clone_emb_df.columns if c.startswith("embedding_")]
tcr_emb_matrix = clone_emb_df[emb_cols].values
logger.info("TCR embedding matrix: %s (n_clones=%d, dim=%d)",
            tcr_emb_matrix.shape, len(clone_ids), tcr_emb_dim)

# Also load clonotype_id if present (for cell-level expansion)
clonotype_col = "clonotype_id" if "clonotype_id" in clone_emb_df.columns else None
clone_clonotypes = clone_emb_df["clonotype_id"].values if clonotype_col else None

# ── Read epitope sequences from FASTA ─────────────────────────────────────────
logger.info("Reading epitope pool from: %s", epitope_fasta)
epitope_seqs = {}
current_header = None
current_seq = []
with open(epitope_fasta, "r") as f:
    for line in f:
        line = line.strip()
        if line.startswith(">"):
            if current_header is not None and current_seq:
                epitope_seqs[current_header] = "".join(current_seq)
            current_header = line.lstrip(">").split()[0]
            current_seq = []
        else:
            current_seq.append(line)
    if current_header is not None and current_seq:
        epitope_seqs[current_header] = "".join(current_seq)

epitope_ids = list(epitope_seqs.keys())
logger.info("Epitope pool: %d peptides (%s …)", len(epitope_ids),
            epitope_ids[0] if epitope_ids else "NONE")

# ── Load XGBoost model + scaler ──────────────────────────────────────────────
model_path = binding_model_dir / "xgboost_model.pkl"
scaler_path = binding_model_dir / "scaler.pkl"

if not model_path.exists() or not scaler_path.exists():
    raise FileNotFoundError(
        f"Binding model directory must contain 'xgboost_model.pkl' and 'scaler.pkl'. "
        f"Found: {list(binding_model_dir.iterdir())}"
    )

logger.info("Loading XGBoost model from: %s", model_path)
with open(model_path, "rb") as f:
    xgb_model = pickle.load(f)

logger.info("Loading StandardScaler from: %s", scaler_path)
with open(scaler_path, "rb") as f:
    scaler = pickle.load(f)

logger.info("Model feature dimension: %d (expecting %d)", xgb_model.n_features_in_, 2 * tcr_emb_dim)

# ── Embed epitope pool (shared across all clones in this sample) ─────────────
logger.info("Embedding %d epitope sequences …", len(epitope_ids))

from transformers import AutoModel, AutoTokenizer
import torch

tokenizer = AutoTokenizer.from_pretrained(esm2_model)
esm_model = AutoModel.from_pretrained(esm2_model)
esm_model.eval()
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
esm_model = esm_model.to(device)
logger.info("ESM-2 device: %s", device)

def embed_seq(seq):
    if not seq or seq in ("NA", "None", ""):
        seq = "X"
    inputs = tokenizer(seq, return_tensors="pt", padding=True,
                       truncation=True, max_length=128)
    inputs = {k: v.to(device) for k, v in inputs.items()}
    with torch.no_grad():
        out = esm_model(**inputs)
    # Mean-pool over tokens, excluding CLS/EOS
    return out.last_hidden_state[:, 1:-1, :].mean(dim=1).cpu().numpy().squeeze()

epitope_embs = {}
for eid, seq in epitope_seqs.items():
    epitope_embs[eid] = embed_seq(seq)

epitope_emb_matrix = np.stack([epitope_embs[eid] for eid in epitope_ids])
logger.info("Epitope embedding matrix: %s", epitope_emb_matrix.shape)

# ── Score all clones × all peptides ──────────────────────────────────────────
logger.info("Scoring %d clones × %d peptides …", len(clone_ids), len(epitope_ids))

n_clones = len(clone_ids)
n_peptides = len(epitope_ids)
feature_dim = 2 * tcr_emb_dim

# Build feature matrix: (clone_emb | epitope_emb) for each clone × peptide pair
# Vectorized: for each peptide, compute concat(tcr_emb, epitope_emb) → score
# Then stack into a (n_clones × n_peptides) score matrix

score_matrix = np.zeros((n_clones, n_peptides), dtype=np.float32)

for p_idx, epitope_id in enumerate(epitope_ids):
    epitope_emb = epitope_embs[epitope_id]
    # Tile epitope emb for all clones: (n_clones, tcr_emb_dim)
    epitope_emb_tiled = np.tile(epitope_emb, (n_clones, 1))
    # Concatenate: (n_clones, 2 * tcr_emb_dim)
    X = np.concatenate([tcr_emb_matrix, epitope_emb_tiled], axis=1)
    if X.shape[1] != feature_dim:
        raise ValueError(
            f"Feature dimension mismatch: model expects {feature_dim}, "
            f"but got {X.shape[1]} (tcr_emb={tcr_emb_dim}, epitope_emb={epitope_emb.shape[0]})"
        )
    X_scaled = scaler.transform(X)
    # decision_function or predict_proba[:, 1] gives probability of "bind"
    if hasattr(xgb_model, "decision_function"):
        scores = xgb_model.decision_function(X_scaled)
    else:
        scores = xgb_model.predict_proba(X_scaled)[:, 1]
    score_matrix[:, p_idx] = scores

logger.info("Score matrix: %s (clones × peptides)", score_matrix.shape)

# ── Build clone-level binding_scores.parquet ──────────────────────────────────
# Columns: clone_id, [epitope_ids...]
# Each cell = binding probability for that clone × peptide
binding_df = pd.DataFrame(score_matrix, columns=epitope_ids, index=clone_ids)
binding_df.index.name = "clone_id"
binding_df = binding_df.reset_index()
logger.info("Binding scores: %d clones × %d peptides", len(binding_df), len(epitope_ids))

clone_binding_out = outdir / f"{meta_id}_binding_scores.parquet"
binding_df.to_parquet(clone_binding_out, index=False)
logger.info("Clone binding scores saved: %s", clone_binding_out)

# ── Build cell-level binding_scores.parquet (one row per cell) ────────────────
# Load TCR metadata to get barcode → clone_id mapping
tcr_csvs = list(Path("${params.outdir}/tcr_quant").glob("*_tcr_metadata.csv"))
# In real run, the merged CSV has all cells. Use the global merged CSV.
merged_csv = Path("${params.outdir}/tcr_quant/merged_tcr_metadata.csv")
if merged_csv.exists():
    cell_df = pd.read_csv(merged_csv)
    logger.info("Cell metadata: %d cells", len(cell_df))

    # Map cells to clone_id: cell's TRA+TRB combo → clone_id
    # clone_emb_df has clone_id assigned by EMBED_CLONES (from deduplicated TRA+TRB)
    # We need to map each cell's TRA/TRB to the same clone_id
    # The clone_df in embed_esm2.py assigns clone_id as sequential index 0..N-1
    # after deduplication by (TRA, TRB) combo.
    # For cell-level expansion: join cell metadata to clone_emb_df on (TRA, TRB)

    # Rebuild clone lookup from clone_emb_df
    # clone_emb_df has clone_id (sequential int) but no TRA/TRB columns
    # We need to re-derive the TRA/TRB → clone_id mapping from the merged TCR metadata.
    # Actually, the merge happens in EMBED_CLONES but clone_id is just row index.
    # For cell-level join: we need to match cells to clone_id via their TRA/TRB combo.

    # Option: load the original cell metadata CSV and match on TRA/TRB
    # Find the cell-level CSV for this sample
    sample_csv = None
    for csv in tcr_csvs:
        if meta_id in str(csv):
            sample_csv = csv
            break

    if sample_csv is None:
        logger.warning("No TCR metadata CSV found for sample %s — cell binding scores may be incomplete", meta_id)
        # Create cell_binding_scores with barcode only (no clone info)
        cell_scores_df = pd.DataFrame({"barcode": [], "clone_id": []})
    else:
        cell_df = pd.read_csv(sample_csv)
        logger.info("Cell metadata for %s: %d cells", meta_id, len(cell_df))

        # Build TRA/TRB → clone_id mapping from clone_emb_df
        # We need to re-deduplicate cells the same way EMBED_CLONES did
        # Clone dedup in embed_esm2.py: deduplicate by (TRA, TRB) keeping first occurrence
        # Assigns clone_id = sequential index after dedup
        # So the clone_id in binding_df corresponds to the first occurrence of each TRA/TRB combo
        # in the merged TCR metadata order.

        # Re-derive: deduplicate the cell_df the same way
        cell_df_dedup = cell_df.drop_duplicates(subset=["TRA", "TRB"], keep="first")
        cell_df_dedup = cell_df_dedup.reset_index(drop=True)
        cell_df_dedup["clone_id"] = cell_df_dedup.index.astype(str)

        # Merge: cell → clone_id → binding scores
        cell_with_clone = cell_df.merge(
            cell_df_dedup[["TRA", "TRB", "clone_id"]],
            on=["TRA", "TRB"],
            how="left",
            suffixes=("", "_dedup")
        )
        # Handle: cell has TRA+TRB but dedup found different clone_id → use first match
        # cells without TCR (TRA/TRB NA) → clone_id = NA

        # Merge binding scores on clone_id
        cell_scores_df = cell_with_clone[["barcode", "clone_id"]].copy()
        cell_scores_df = cell_scores_df.merge(binding_df, on="clone_id", how="left")

        # Drop clone_id from final output (barcode is the join key back to Seurat)
        cell_scores_df = cell_scores_df.drop(columns=["clone_id"])

        logger.info("Cell binding scores: %d cells × %d peptides",
                    len(cell_scores_df), len(epitope_ids))
else:
    logger.warning("merged_tcr_metadata.csv not found — cannot produce cell-level binding scores")
    cell_scores_df = pd.DataFrame({"barcode": []})

cell_binding_out = outdir / f"{meta_id}_cell_binding_scores.parquet"
cell_scores_df.to_parquet(cell_binding_out, index=False)
logger.info("Cell binding scores saved: %s", cell_binding_out)

logger.info("Predict binding complete for %s.", meta_id)