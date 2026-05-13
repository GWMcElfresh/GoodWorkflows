#!/usr/bin/env python3
# NUMBA_DISABLE_JIT=1
"""
Nextflow template: tcr_umap.py
TCR_UMAP — Leiden clustering + UMAP projection on ESM-2 clone embeddings.

Visualizes the TCR clone embedding space (UNSUPERVISED — no epitope required):
  1. Load ESM-2 clone embeddings (one row per unique TCR clone)
  2. Leiden clustering on the embedding space
  3. UMAP projection
  4. Count n_cells per clone from the cell-level TCR metadata
  5. Output clone_metadata.parquet for JOIN_SEURAT

Outputs:
  - clone_metadata.parquet
      clonotype_id  (clone identifier from deduplication)
      umap_x, umap_y  (2D projection coordinates)
      cluster         (Leiden cluster label)
      n_cells         (number of cells with this clone)
      embedding_*     (optional: ESM-2 dimensions, excluded to keep file small)
"""

import logging
from pathlib import Path

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
logger = logging.getLogger("tcr_umap")

import pandas as pd
import numpy as np

# ── Parameters ────────────────────────────────────────────────────────────────
clone_emb_parquet = Path("${clone_embeddings_parquet}").resolve()
outdir = Path("${params.outdir}/tcr_epitope").resolve()
outdir.mkdir(parents=True, exist_ok=True)

resolution = float("${leiden_resolution}")

logger.info("Clone embeddings: %s", clone_emb_parquet)
logger.info("Leiden resolution: %s", resolution)

# ── Load clone embeddings ─────────────────────────────────────────────────────
logger.info("Loading clone embeddings …")
clone_emb_df = pd.read_parquet(clone_emb_parquet)
logger.info("Clone embeddings shape: %s", clone_emb_df.shape)

# Identify clone_id column
if "clone_id" in clone_emb_df.columns:
    clone_id_col = "clone_id"
elif "clonotype_id" in clone_emb_df.columns:
    clone_id_col = "clonotype_id"
else:
    raise ValueError(f"clone_embeddings.parquet must have 'clone_id' or 'clonotype_id' column. Found: {list(clone_emb_df.columns)}")

clone_ids = clone_emb_df[clone_id_col].values.astype(str)
emb_cols = [c for c in clone_emb_df.columns if c.startswith("embedding_")]
emb_matrix = clone_emb_df[emb_cols].values.astype(np.float32)
logger.info("Embedding matrix shape: %s (n_clones=%d, dim=%d)",
            emb_matrix.shape, len(clone_ids), emb_matrix.shape[1])

# ── Leiden clustering ──────────────────────────────────────────────────────────
logger.info("Running Leiden clustering (resolution=%.2f) …", resolution)

use_scanpy = False
try:
    import scanpy as sc
    USE_SCANPY = True
    use_scanpy = True
except ImportError:
    USE_SCANPY = False

if use_scanpy:
    adata = sc.AnnData(X=emb_matrix)
    adata.obs_names = clone_ids

    sc.pp.neighbors(adata, n_neighbors=15, use_rep="X")
    sc.tl.leiden(adata, resolution=resolution, key_added="cluster")
    sc.tl.umap(adata, min_dist=0.3)

    leiden_clusters = adata.obs["cluster"].values.astype(str)
    umap_x = adata.obsm["X_umap"][:, 0]
    umap_y = adata.obsm["X_umap"][:, 1]
else:
    from sklearn.cluster import KMeans
    from sklearn.decomposition import PCA

    n_clusters = max(2, int(np.sqrt(len(clone_ids) / 10)))
    logger.warning("scanpy not available — using KMeans fallback (k=%d)", n_clusters)

    km = KMeans(n_clusters=n_clusters, random_state=42, n_init="auto")
    leiden_clusters = km.fit_predict(emb_matrix).astype(str)

    pca = PCA(n_components=2, random_state=42)
    proj = pca.fit_transform(emb_matrix)
    umap_x, umap_y = proj[:, 0], proj[:, 1]

logger.info("Clustering done. Unique clusters: %s", sorted(set(leiden_clusters)))

# ── Count n_cells per clone ─────────────────────────────────────────────────────
# n_cells = how many cells in the original TCR metadata share this clone
# We count from the merged TCR metadata CSV (produced by MERGE_TCR_METADATA)
# For each unique TRA+TRB combo in the merged CSV, count occurrences → n_cells
logger.info("Counting cells per clone from merged TCR metadata …")

merged_csv = Path("${params.outdir}/tcr_quant/merged_tcr_metadata.csv")
if merged_csv.exists():
    cell_df = pd.read_csv(merged_csv)
    logger.info("Merged TCR metadata: %d cell records", len(cell_df))

    # Count cells per unique TRA+TRB combo
    tra_col = "TRA" if "TRA" in cell_df.columns else None
    trb_col = "TRB" if "TRB" in cell_df.columns else None

    if tra_col and trb_col:
        # Build clone key = TRA|TRB (same as EMBED_CLONES dedup key)
        cell_df["clone_key"] = (
            cell_df[tra_col].astype(str) + "|" + cell_df[trb_col].astype(str)
        )
        n_cells_per_clone = cell_df.groupby("clone_key").size().reset_index(name="n_cells")
        logger.info("Unique clones in cell metadata: %d", len(n_cells_per_clone))

        # Map clone_id to n_cells via clone_key
        # clone_id in clone_emb_df = row index after (TRA, TRB) dedup in EMBED_CLONES
        # We need to rebuild this mapping: deduplicate the same way
        dedup_df = cell_df.drop_duplicates(subset=["clone_key"], keep="first").copy()
        dedup_df = dedup_df.reset_index(drop=True)
        dedup_df["clone_id_str"] = dedup_df.index.astype(str)

        # Merge: clone_id (from clone_emb_df) → n_cells
        # clone_ids from clone_emb_df are sequential 0, 1, 2, ... (assigned by EMBED_CLONES)
        # These should match the row index in dedup_df (same dedup order)
        n_cells_lookup = dict(zip(n_cells_per_clone["clone_key"], n_cells_per_clone["n_cells"]))
        clone_key_lookup = dict(zip(dedup_df["clone_id_str"], dedup_df["clone_key"]))

        n_cells_vec = []
        for cid in clone_ids:
            ck = clone_key_lookup.get(str(cid), None)
            n_cells_vec.append(n_cells_lookup.get(ck, 1) if ck else 1)
        n_cells_arr = np.array(n_cells_vec, dtype=np.int32)
    else:
        logger.warning("TRA/TRB columns not found in merged CSV — setting n_cells=1 for all")
        n_cells_arr = np.ones(len(clone_ids), dtype=np.int32)
else:
    logger.warning("merged_tcr_metadata.csv not found — setting n_cells=1 for all clones")
    n_cells_arr = np.ones(len(clone_ids), dtype=np.int32)

logger.info("n_cells range: %d – %d", n_cells_arr.min(), n_cells_arr.max())

# ── Build output dataframe ─────────────────────────────────────────────────────
result_df = pd.DataFrame({
    "clonotype_id": clone_ids,
    "umap_x": umap_x,
    "umap_y": umap_y,
    "cluster": leiden_clusters,
    "n_cells": n_cells_arr,
})

logger.info("Writing clone_metadata.parquet …")
result_df.to_parquet(outdir / "clone_metadata.parquet", index=False)
logger.info("Done. Outputs in: %s", outdir)
logger.info("TCR UMAP complete.")