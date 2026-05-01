#!/usr/bin/env python3
"""
Nextflow template: integrate.py
scMODAL cross-species latent embedding for SCMODAL_INTEGRATE.

Nextflow substitutions (resolved before Python runs):
  ${harmonized_dir}               – path to GENE_HARMONIZE outputs
  ${params.scmodal_batch_size}    – int
  ${params.scmodal_training_steps}– int
  ${params.scmodal_latent}        – int
  ${params.scmodal_neighbors}     – int
  ${params.leiden_resolution}     – float
"""

import json
import os
import pathlib
import shutil
import subprocess
import sys

import anndata as ad
import numpy as np
import pandas as pd
import scanpy as sc
import torch
from scipy import sparse

from scmodal.model import Model

# ---------------------------------------------------------------------------
# Nextflow-injected parameters
# ---------------------------------------------------------------------------
HARMONIZED_DIR   = pathlib.Path("${harmonized_dir}")
BASE_BATCH_SIZE  = int("${params.scmodal_batch_size}")
ATTEMPT          = int("${task.attempt}")
# Reduce batch size by 10 % per retry (attempt 1 = full size).
# Floor at 250 to avoid training instability.
BATCH_SIZE       = max(250, int(BASE_BATCH_SIZE * (0.9 ** (ATTEMPT - 1))))
TRAINING_STEPS = int("${params.scmodal_training_steps}")
N_LATENT = int("${params.scmodal_latent}")
N_NEIGHBORS = int("${params.scmodal_neighbors}")
LEIDEN_RESOLUTION = float("${params.leiden_resolution}")

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
out_dir = pathlib.Path("model_outputs")
out_dir.mkdir(exist_ok=True)

try:
    result = subprocess.run(
        ["nvidia-smi"], capture_output=True, text=True, check=True
    )
    (out_dir / "gpu_info.txt").write_text(result.stdout)
except (subprocess.CalledProcessError, FileNotFoundError) as exc:
    msg = f"WARNING: nvidia-smi failed: {exc}\\n"
    (out_dir / "gpu_info.txt").write_text(msg)

# ---------------------------------------------------------------------------
# Load manifest and AnnData inputs
# ---------------------------------------------------------------------------
manifest_path = HARMONIZED_DIR / "integration_manifest.csv"
if not manifest_path.exists():
    raise RuntimeError(
        f"integration_manifest.csv not found in {HARMONIZED_DIR}. "
        "Ensure GENE_HARMONIZE completed successfully."
    )

manifest = pd.read_csv(manifest_path)
manifest = manifest.sort_values("order_index").reset_index(drop=True)
if manifest.empty:
    raise RuntimeError("integration_manifest.csv is empty.")

adatas = []
for row in manifest.itertuples(index=False):
    h5ad_path = HARMONIZED_DIR / row.h5ad_file
    if not h5ad_path.exists():
        raise RuntimeError(
            f"Expected h5ad file not found: {h5ad_path}"
        )
    adata = sc.read_h5ad(h5ad_path)
    if sparse.issparse(adata.X):
        adata.X = adata.X.toarray().astype(np.float32)
    else:
        adata.X = np.asarray(adata.X, dtype=np.float32)
    adatas.append(adata)

# ---------------------------------------------------------------------------
# Model training
# ---------------------------------------------------------------------------
if ATTEMPT > 1:
    print(
        f"SCMODAL_INTEGRATE: retry attempt {ATTEMPT} — "
        f"using batch_size={BATCH_SIZE} (base={BASE_BATCH_SIZE}).",
        flush=True,
    )

model_dir = out_dir / "scmodal_model"
try:
    model = Model(
        batch_size=BATCH_SIZE,
        training_steps=TRAINING_STEPS,
        n_latent=N_LATENT,
        n_KNN=N_NEIGHBORS,
        model_path=str(model_dir),
        result_path=str(out_dir),
    )

    if len(adatas) == 2:
        n_shared_path = HARMONIZED_DIR / "n_shared.txt"
        if not n_shared_path.exists():
            raise RuntimeError(f"n_shared.txt not found in {HARMONIZED_DIR}")
        shared_gene_num = int(n_shared_path.read_text().strip())
        model.preprocess(adatas[0], adatas[1], shared_gene_num)
        model.train()
        model.eval()
    elif len(adatas) > 2:
        if not hasattr(model, "integrate_datasets_feats"):
            raise RuntimeError(
                f"scMODAL Model does not expose integrate_datasets_feats — "
                f"multi-species integration (n={len(adatas)}) is not supported by "
                "the installed scmodal version."
            )
        input_feats = [adata.X for adata in adatas]
        paired_inputs = [
            [input_feats[idx], input_feats[idx + 1]]
            for idx in range(len(input_feats) - 1)
        ]
        model.integrate_datasets_feats(
            input_feats=input_feats, paired_input_MNN=paired_inputs
        )
    else:
        raise RuntimeError(
            f"SCMODAL_INTEGRATE requires at least 2 AnnData objects; got {len(adatas)}."
        )
except torch.cuda.OutOfMemoryError:
    print(
        f"SCMODAL_INTEGRATE: CUDA out-of-memory on attempt {ATTEMPT} "
        f"with batch_size={BATCH_SIZE}. "
        "Exiting with code 42 to trigger Nextflow retry with a smaller batch size.",
        flush=True,
    )
    sys.exit(42)

# Validate that model produced a latent embedding
if not hasattr(model, "latent") or model.latent is None:
    raise RuntimeError(
        "scMODAL model.latent is None after training — "
        "training may have failed silently. Check logs above."
    )

# ---------------------------------------------------------------------------
# Combine outputs and cluster
# ---------------------------------------------------------------------------
combined = ad.concat(
    adatas,
    join="inner",
    merge="same",
    label="integration_species",
    keys=manifest["species"].tolist(),
    index_unique=None,
)
combined.obsm["X_scmodal"] = model.latent.astype(np.float32, copy=False)

n_neighbors_capped = min(N_NEIGHBORS, max(2, combined.n_obs - 1))
sc.pp.neighbors(combined, use_rep="X_scmodal", n_neighbors=n_neighbors_capped)
sc.tl.umap(combined)
sc.tl.leiden(combined, resolution=LEIDEN_RESOLUTION)

combined.uns["scmodal"] = {
    "species_order": manifest["species"].tolist(),
    "n_latent": N_LATENT,
    "training_steps": TRAINING_STEPS,
    "device": str(model.device),
}

combined.write_h5ad(out_dir / "latent_clustered.h5ad")

# ---------------------------------------------------------------------------
# Copy supporting files
# ---------------------------------------------------------------------------
ckpt_src = model_dir / "ckpt.pth"
if not ckpt_src.exists():
    raise RuntimeError(
        f"Expected checkpoint file not found: {ckpt_src}. "
        "Training may not have completed."
    )
shutil.copy2(ckpt_src, out_dir / "ckpt.pth")
shutil.copy2(
    HARMONIZED_DIR / "integration_manifest.csv",
    out_dir / "integration_manifest.csv",
)
shutil.copy2(
    HARMONIZED_DIR / "shared_genes.csv",
    out_dir / "shared_genes.csv",
)

# ---------------------------------------------------------------------------
# Write summaries
# ---------------------------------------------------------------------------
training_summary = pd.DataFrame(
    [
        {
            "n_species": len(adatas),
            "n_cells": int(combined.n_obs),
            "n_genes": int(combined.n_vars),
            "n_latent": N_LATENT,
            "training_steps": TRAINING_STEPS,
            "batch_size": BATCH_SIZE,
            "base_batch_size": BASE_BATCH_SIZE,
            "attempt": ATTEMPT,
            "train_time_seconds": float(getattr(model, "train_time", float("nan"))),
            "eval_time_seconds": float(getattr(model, "eval_time", float("nan"))),
            "device": str(model.device),
        }
    ]
)
training_summary.to_csv(out_dir / "training_history.csv", index=False)

(out_dir / "run_summary.json").write_text(
    json.dumps(
        {
            "species_order": manifest["species"].tolist(),
            "n_cells": int(combined.n_obs),
            "n_genes": int(combined.n_vars),
            "n_latent": N_LATENT,
            "device": str(model.device),
        },
        indent=2,
    )
)

# ---------------------------------------------------------------------------
# Output validation
# ---------------------------------------------------------------------------
required_outputs = [
    out_dir / "latent_clustered.h5ad",
    out_dir / "ckpt.pth",
    out_dir / "training_history.csv",
    out_dir / "run_summary.json",
]
for path in required_outputs:
    if not path.exists():
        raise RuntimeError(f"SCMODAL_INTEGRATE: expected output not created: {path}")

print(
    f"SCMODAL_INTEGRATE complete: {len(adatas)} species, "
    f"{int(combined.n_obs)} cells, "
    f"n_latent={N_LATENT}, "
    f"device={model.device}.",
    flush=True,
)
