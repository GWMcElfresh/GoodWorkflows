#!/usr/bin/env python3
"""
Nextflow template: merge_counts.py
Merges per-sample 10x-like count matrix directories into a single joint
AnnData (.h5ad) file and writes a genes.txt gene list.

Used by process NMF_VAE_MERGE_COUNTS.
"""

import pathlib

import anndata as ad
import numpy as np
import pandas as pd
from scipy import io, sparse


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def read_count_dir(count_dir):
    """Read a single *_counts directory and return an AnnData object.

    Expects: matrix.mtx, features.tsv, barcodes.tsv, obs_meta.csv
    """
    for required in ("features.tsv", "barcodes.tsv", "obs_meta.csv", "matrix.mtx"):
        if not (count_dir / required).exists():
            raise RuntimeError(
                f"Missing required file {required!r} in {count_dir}"
            )

    genes = pd.read_csv(
        count_dir / "features.tsv", sep=chr(9), header=None
    )[0].astype(str).tolist()
    barcodes = pd.read_csv(
        count_dir / "barcodes.tsv", sep=chr(9), header=None
    )[0].astype(str).tolist()
    obs = pd.read_csv(count_dir / "obs_meta.csv", index_col=0)
    obs.index = obs.index.astype(str)
    obs = obs.reindex(barcodes)

    if obs.isnull().all(axis=1).any():
        missing = obs.index[obs.isnull().all(axis=1)].tolist()[:5]
        raise RuntimeError(
            f"obs_meta rows did not align to barcodes for {count_dir}: {missing}"
        )

    sample_id = (
        str(obs["sample_id"].iloc[0])
        if "sample_id" in obs.columns
        else count_dir.name.replace("_counts", "")
    )
    species = str(obs["species"].iloc[0]) if "species" in obs.columns else "unknown"

    # matrix.mtx is genes x barcodes; transpose to cells x genes
    matrix = io.mmread(count_dir / "matrix.mtx").tocsr().transpose().tocsr()

    if matrix.shape != (len(barcodes), len(genes)):
        raise RuntimeError(
            f"Matrix shape mismatch for {count_dir}: got {matrix.shape}, "
            f"expected {(len(barcodes), len(genes))}"
        )

    obs = obs.copy()
    obs["sample_id"] = sample_id
    obs["species"] = species
    obs["original_barcode"] = barcodes
    obs.index = pd.Index(
        [f"{sample_id}:{barcode}" for barcode in barcodes], name="cell_id"
    )

    var = pd.DataFrame(index=pd.Index(genes, name="feature_name"))
    var["feature_name"] = var.index.astype(str)

    return ad.AnnData(X=matrix, obs=obs, var=var)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

count_dirs = sorted(pathlib.Path(".").glob("*_counts"))
if not count_dirs:
    raise RuntimeError(
        "No per-sample counts directories were staged for NMF_VAE_MERGE_COUNTS. "
        "Expected directories matching '*_counts' in the work directory."
    )

# Read all samples
adatas = []
for count_dir in count_dirs:
    print(f"Reading {count_dir} ...", flush=True)
    adata = read_count_dir(count_dir)
    adatas.append(adata)

print(f"Loaded {len(adatas)} sample(s).", flush=True)

# Determine shared gene set (intersection across all samples)
all_gene_sets = [set(adata.var_names.tolist()) for adata in adatas]
shared_genes = set.intersection(*all_gene_sets)

if not shared_genes:
    raise RuntimeError(
        "No shared genes across all samples. Cannot merge."
    )

shared_genes = sorted(shared_genes)
print(f"Shared genes across all samples: {len(shared_genes)}", flush=True)

# Filter each AnnData to shared genes and stack
filtered_adatas = []
for adata in adatas:
    keep = [g in shared_genes for g in adata.var_names.tolist()]
    filtered_adatas.append(adata[:, keep].copy())

# Concatenate vertically (stack cells)
merged = ad.concat(filtered_adatas, axis=0, join="outer", merge="same")

# Ensure .X is sparse CSR
if sparse.issparse(merged.X):
    merged.X = merged.X.tocsr()

# Sort features to match shared_genes order
gene_order = {gene: idx for idx, gene in enumerate(shared_genes)}
col_map = np.array([gene_order[g] for g in merged.var_names.tolist()])
merged.X = merged.X[:, col_map]
merged.var_names = shared_genes

# Ensure .var has feature_name column
merged.var["feature_name"] = merged.var_names.astype(str)

# Ensure .obs has required columns
if "sample_id" not in merged.obs.columns:
    merged.obs["sample_id"] = "unknown"
if "species" not in merged.obs.columns:
    merged.obs["species"] = "unknown"

print(f"Merged matrix shape: {merged.X.shape[0]} cells x {merged.X.shape[1]} genes", flush=True)

# Convert all obs columns to str to satisfy h5py's strict string-type requirement
for col in merged.obs.columns:
    if merged.obs[col].dtype != object:
        merged.obs[col] = merged.obs[col].astype(str)

# Write merged .h5ad
merged.write_h5ad("merged_counts.h5ad")
print("Wrote merged_counts.h5ad", flush=True)

# Write genes.txt
pathlib.Path("genes.txt").write_text(chr(10).join(shared_genes) + chr(10))
print(f"Wrote genes.txt ({len(shared_genes)} genes)", flush=True)

# Validate
for expected in ("merged_counts.h5ad", "genes.txt"):
    if not pathlib.Path(expected).exists():
        raise RuntimeError(
            f"NMF_VAE_MERGE_COUNTS: expected output not created: {expected}"
        )

print("NMF_VAE_MERGE_COUNTS complete.", flush=True)
