#!/usr/bin/env python3
"""
Nextflow template: train_gex_mil.py
TRAIN_GEX_MIL — scVI + attention-MIL donor-level classification via mil-ton.
"""

import json
import logging
import sys
from pathlib import Path

logging.basicConfig(level=logging.INFO, format="%(message)s")
logger = logging.getLogger("train_gex_mil")

import torch
from torch.utils.data import DataLoader, Subset

# mil-ton imports
from mil_ton.config import Config, save_config
from mil_ton.data.ingestion import load_data
from mil_ton.models.mil_model import MILModel
from mil_ton.models.scvi_model import save_scvi, train_scvi
from mil_ton.training.dataset import DonorDataset, split_donors
from mil_ton.training.trainer import Trainer
from mil_ton.inference.predict import export_predictions, predict_donors
from mil_ton.inference.interpret import export_top_attended_cells, get_attention_weights

# ── Resolve inputs relative to task work dir ──────────────────────────
workdir = Path(".").resolve()
h5ad_path = workdir / "${merged_h5ad}"
meta_path = workdir / "${cell_metadata}"

# ── Build minimal YAML config from Nextflow params ─────────────────────
outdir = Path("${params.outdir}/gex_mil").resolve()
outdir.mkdir(parents=True, exist_ok=True)

cfg = Config()
cfg.data.donor_col       = params.milton_donor_col
cfg.data.label_cols      = [params.milton_label_col]
cfg.data.task            = "classification"
cfg.data.cells_per_donor = params.milton_cells_per_donor
cfg.scvi.n_latent        = params.milton_n_latent
cfg.scvi.batch_key       = params.milton_batch_key or None
cfg.mil.encoder_dims     = [int(d) for d in str(params.milton_encoder_dims).split(",")]
cfg.mil.attention_dim   = params.milton_attention_dim
cfg.mil.dropout          = params.mil_dropout
cfg.training.epochs       = params.mil_epochs
cfg.training.seed        = params.milton_seed
cfg.training.train_frac   = 0.7
cfg.training.val_frac    = 0.15
cfg.training.batch_size  = 1
save_config(cfg, outdir / "config.yaml")

# ── Load data ─────────────────────────────────────────────────────────
logger.info("Loading GEX from %s", h5ad_path)
adata = load_data(str(h5ad_path.resolve().parent),  # load_data reads the h5ad from parent dir
                  donor_col=cfg.data.donor_col,
                  label_cols=cfg.data.label_cols)

# ── scVI ───────────────────────────────────────────────────────────────
logger.info("Training scVI (latent=%d)", cfg.scvi.n_latent)
adata, scvi_model = train_scvi(adata, cfg.scvi)
save_scvi(scvi_model, outdir / "scvi_model")

latent_dim = adata.obsm["X_scVI"].shape[1]

# ── Donor splits ───────────────────────────────────────────────────────
all_donors = adata.obs[cfg.data.donor_col].unique().tolist()
train_donors, val_donors, test_donors = split_donors(
    all_donors,
    cfg.training.train_frac,
    cfg.training.val_frac,
    seed=cfg.training.seed,
)
logger.info("Donors: train=%d val=%d test=%d", len(train_donors), len(val_donors), len(test_donors))

def make_subset(donor_list):
    ds = DonorDataset(
        adata,
        donor_col=cfg.data.donor_col,
        label_cols=cfg.data.label_cols,
        cells_per_donor=cfg.data.cells_per_donor,
        task=cfg.data.task,
        seed=cfg.training.seed,
    )
    indices = [ds.donors.index(d) for d in donor_list if d in ds.donors]
    return Subset(ds, indices)

train_ds = make_subset(train_donors)
val_ds   = make_subset(val_donors)
test_ds  = make_subset(test_donors)

train_loader = DataLoader(train_ds, batch_size=1, shuffle=True)
val_loader   = DataLoader(val_ds,   batch_size=1)
test_loader  = DataLoader(test_ds,  batch_size=1)

# ── Number of classes ───────────────────────────────────────────────────
unique_labels = adata.obs[cfg.data.label_cols[0]].nunique()
n_classes = 1 if unique_labels <= 2 else unique_labels
logger.info("Classes: %d", n_classes)

# ── MIL model ──────────────────────────────────────────────────────────
torch.manual_seed(cfg.training.seed)
model = MILModel(
    input_dim=latent_dim,
    encoder_dims=cfg.mil.encoder_dims,
    attention_dim=cfg.mil.attention_dim,
    n_classes=n_classes,
    task=cfg.data.task,
    dropout=cfg.mil.dropout,
    n_heads=1,
)

trainer = Trainer(
    model=model,
    config=cfg.training,
    task=cfg.data.task,
    n_classes=n_classes,
    output_dir=outdir,
)

logger.info("Training MIL model …")
history = trainer.train(train_loader, val_loader)

# ── Test evaluation ────────────────────────────────────────────────────
model.load_state_dict(torch.load(outdir / "model.pt",
                                  map_location=trainer.device))
test_metrics = trainer.evaluate(test_loader)
logger.info("Test metrics: %s", test_metrics)

with (outdir / "metrics.json").open("w") as fh:
    json.dump({"test": test_metrics, "history": history}, fh, indent=2)

# ── Predictions ─────────────────────────────────────────────────────────
full_ds = DonorDataset(
    adata,
    donor_col=cfg.data.donor_col,
    label_cols=cfg.data.label_cols,
    cells_per_donor=cfg.data.cells_per_donor,
    task=cfg.data.task,
    seed=cfg.training.seed,
)
full_loader = DataLoader(full_ds, batch_size=1)
predictions = predict_donors(model, full_loader, task=cfg.data.task)
export_predictions(predictions, outdir / "predictions.csv")

# ── Attention / saliency ───────────────────────────────────────────────
attention_dict = get_attention_weights(model, full_loader)
export_top_attended_cells(
    adata, attention_dict,
    donor_col=cfg.data.donor_col,
    output_path=outdir / "attention_weights.csv",
)

logger.info("GEX MIL complete. Outputs in %s", outdir)
