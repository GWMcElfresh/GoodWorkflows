#!/usr/bin/env python3
"""
Nextflow template: integrate.py
scMODAL cross-species latent embedding for SCMODAL_INTEGRATE.

Nextflow substitutions (resolved before Python runs):
  ${harmonized_dir}               – path to GENE_HARMONIZE outputs
  ${params.scmodal_batch_size}    – int (base; reduced 10 % per retry attempt)
  ${params.scmodal_training_steps}– int
  ${params.scmodal_latent}        – int
  ${params.scmodal_neighbors}     – int
  ${params.leiden_resolution}     – float
  ${task.attempt}                 – int (Nextflow retry counter, 1-based)
"""

import json
import math
import os
import pathlib
import shutil
import subprocess
import sys
import traceback

# Must be set before PyTorch initialises CUDA.
# expandable_segments: True lets the CUDA caching allocator grow existing
# allocations rather than failing when a large contiguous block is needed
# but the pool is fragmented (the typical OOM pattern in scMODAL's geometric
# loss, which materialises a (batch, batch, n_genes) intermediate tensor).
os.environ.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")

import anndata as ad
import numpy as np
import pandas as pd
import scanpy as sc
import torch
from scipy import sparse

from scmodal.model import Model


# ---------------------------------------------------------------------------
# OOM helpers
# ---------------------------------------------------------------------------

def _is_oom(exc: BaseException) -> bool:
    """Return True for CUDA out-of-memory errors across all PyTorch versions."""
    if hasattr(torch.cuda, "OutOfMemoryError") and isinstance(
        exc, torch.cuda.OutOfMemoryError
    ):
        return True
    return isinstance(exc, RuntimeError) and "out of memory" in str(exc).lower()


def _log_oom(exc: BaseException, phase: str) -> None:
    """Print full diagnostic, then exit with sentinel code 42 for Nextflow retry."""
    sep = "=" * 70
    print(f"\n{sep}", flush=True)
    print(
        f"SCMODAL_INTEGRATE OOM — phase='{phase}', "
        f"attempt={ATTEMPT}, batch_size={BATCH_SIZE} (base={BASE_BATCH_SIZE})",
        flush=True,
    )
    print("\n--- Python traceback ---", flush=True)
    traceback.print_exc(file=sys.stdout)
    sys.stdout.flush()
    if torch.cuda.is_available():
        print("\n--- CUDA memory summary ---", flush=True)
        try:
            print(torch.cuda.memory_summary(device=0, abbreviated=False), flush=True)
        except Exception as _mem_exc:
            print(f"(memory_summary unavailable: {_mem_exc})", flush=True)
    print(sep, flush=True)
    print(
        "Exiting with code 42 — Nextflow will retry with a smaller batch size.",
        flush=True,
    )
    sys.exit(42)


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
# Pre-flight: data summary + VRAM budget check
# ---------------------------------------------------------------------------
print("SCMODAL_INTEGRATE: dataset summary", flush=True)
for _i, (_adata, _row) in enumerate(zip(adatas, manifest.itertuples(index=False))):
    print(
        f"  species[{_i}] {_row.species}: {_adata.n_obs:,} cells × {_adata.n_vars:,} genes",
        flush=True,
    )

if torch.cuda.is_available():
    _props        = torch.cuda.get_device_properties(0)
    _total_gib    = _props.total_memory / 2**30
    _free_gib     = (_props.total_memory - torch.cuda.memory_reserved(0)) / 2**30
    _n_genes_max  = max(a.n_vars for a in adatas)
    # scMODAL's geometric loss materialises (batch, batch, n_genes) float32 tensors
    # twice per training step (K_A and K_B, computed sequentially); peak is one at a
    # time, but retain_graph=True in the discriminator loop can prevent the allocator
    # from reusing blocks, so we budget for both.
    _kmat_gib     = 2 * BATCH_SIZE**2 * _n_genes_max * 4 / 2**30
    _safe_batch   = int(math.sqrt(_free_gib * 0.45 * 2**30 / _n_genes_max / 4))
    print(
        f"SCMODAL_INTEGRATE: GPU={_props.name} — "
        f"{_free_gib:.2f}/{_total_gib:.2f} GiB free, "
        f"n_genes_max={_n_genes_max}, batch_size={BATCH_SIZE}, "
        f"estimated K-matrix peak={_kmat_gib:.2f} GiB "
        f"(safe batch_size ≤ {_safe_batch})",
        flush=True,
    )
    if _kmat_gib > _free_gib * 0.90:
        print(
            f"  WARNING: K-matrix estimate ({_kmat_gib:.2f} GiB) exceeds 90 % of free "
            f"VRAM ({_free_gib:.2f} GiB). OOM during training is very likely.",
            flush=True,
        )

# ---------------------------------------------------------------------------
# Model training
# ---------------------------------------------------------------------------
if ATTEMPT > 1:
    print(
        f"SCMODAL_INTEGRATE: retry attempt {ATTEMPT} — "
        f"batch_size={BATCH_SIZE} (base={BASE_BATCH_SIZE}).",
        flush=True,
    )

model_dir = out_dir / "scmodal_model"

# --- Phase 1: model creation + training ---
torch.cuda.empty_cache()
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
        # integrate_datasets_feats handles training + latent inference internally.
        model.integrate_datasets_feats(
            input_feats=input_feats, paired_input_MNN=paired_inputs
        )
    else:
        raise RuntimeError(
            f"SCMODAL_INTEGRATE requires at least 2 AnnData objects; got {len(adatas)}."
        )
except Exception as exc:
    if _is_oom(exc):
        _log_oom(exc, "training")
    raise

# --- Phase 2: inference / latent extraction (2-species path only) ---
# model.eval() loads ALL cells onto the GPU in one shot, with no batching.
# Without torch.no_grad(), PyTorch stores activation buffers for every forward
# pass, roughly doubling peak VRAM.  Wrapping in no_grad() cuts that in half.
# We also flush the CUDA allocator cache so freed training tensors (model
# weights that were overwritten, optimizer states) don't fragment the pool.
if len(adatas) == 2:
    torch.cuda.empty_cache()
    try:
        with torch.no_grad():
            model.eval()
    except Exception as exc:
        if _is_oom(exc):
            _log_oom(exc, "inference (eval)")
        raise

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
