#!/usr/bin/env python3
"""
Nextflow template: train_tcr_mil.py
TRAIN_TCR_MIL — BertTCR CNN-MIL donor-level classification via mil-ton.
"""

import json
import logging
from pathlib import Path

logging.basicConfig(level=logging.INFO, format="%(message)s")
logger = logging.getLogger("train_tcr_mil")

import torch
from torch.utils.data import DataLoader

from mil_ton.models.tcr.dataset import TCRSequenceDataset
from mil_ton.models.tcr.model import BertTCRModel
from mil_ton.models.tcr.encoder import TCRBertEncoder
from mil_ton.training.tcr_trainer import TCRTrainer

outdir = Path("${params.outdir}/tcr_mil").resolve()
outdir.mkdir(parents=True, exist_ok=True)

# ── Parameters from Nextflow ────────────────────────────────────────────
n_tcrs           = int("${params.tcrMilNTcrs}")
max_tcr_len      = int("${params.tcrMilMaxTcrLen}")
bert_model_name  = "${params.tcrMilBertModel}"
bert_hidden      = int("${params.tcrMilBertHidden}")
n_classes        = int("${params.tcrMilNClasses}")
n_ensemble       = int("${params.tcrMilNEnsemble}")
epochs           = int("${params.tcrMilEpochs}")
lr               = float("${params.tcrMilLR}")
weight_decay     = float("${params.tcrMilWeightDecay}")
seed             = int("${params.tcrMilSeed}")
label_col        = "${params.tcrMilLabelCol}"

# ── Load TCR metadata CSV ───────────────────────────────────────────────
import pandas as pd
tcr_df = pd.read_csv("${tcr_metadata_csv}")
logger.info("Loaded %d TCR records from %s", len(tcr_df), "${tcr_metadata_csv}")

required_cols = {"CDR3_seq", "SubjectId", label_col}
missing = required_cols - set(tcr_df.columns)
if missing:
    raise ValueError(f"TCR metadata missing required columns: {missing}")

# ── Build donor-level MIL bags ──────────────────────────────────────────
# Group by SubjectId and label; TCRSequenceDataset handles bag construction
ds = TCRSequenceDataset(
    df         = tcr_df[["CDR3_seq", "SubjectId", label_col]].rename(
                     columns={"CDR3_seq": "CDR3_seq", label_col: "label"}),
    n_tcrs     = n_tcrs,
    seq_col    = "CDR3_seq",
    label_col  = "label",
    max_tcr_len= max_tcr_len,
    seed       = seed,
)

logger.info("Donors: %d  |  Bag size: %d", len(ds.donors), n_tcrs)

# ── Train / val / test split ────────────────────────────────────────────
all_donors = ds.donors
n = len(all_donors)
n_train = int(0.7 * n)
n_val   = int(0.15 * n)
indices = list(range(n))
import random
random.seed(seed)
random.shuffle(indices)
train_idx, val_idx, test_idx = indices[:n_train], indices[n_train:n_train+n_val], indices[n_train+n_val:]

from torch.utils.data import Subset
train_ds = Subset(ds, train_idx)
val_ds   = Subset(ds, val_idx)
test_ds  = Subset(ds, test_idx)

train_loader = DataLoader(train_ds, batch_size=1, shuffle=True)
val_loader   = DataLoader(val_ds,   batch_size=1)
test_loader  = DataLoader(test_ds,  batch_size=1)

logger.info("Split: train=%d val=%d test=%d", len(train_ds), len(val_ds), len(test_ds))

# ── Build model ─────────────────────────────────────────────────────────
torch.manual_seed(seed)
model = BertTCRModel(
    n_tcrs            = n_tcrs,
    n_classes         = n_classes,
    filter_num        = [3, 2, 1],
    kernel_size       = [2, 3, 4],
    max_tcr_len       = max_tcr_len,
    dropout           = 0.4,
    n_ensemble        = n_ensemble,
    bert_hidden_size  = bert_hidden,
)

# ── Train ────────────────────────────────────────────────────────────────
trainer = TCRTrainer(
    model        = model,
    epochs       = epochs,
    lr           = lr,
    weight_decay = weight_decay,
    output_dir   = outdir,
)

logger.info("Training BertTCR model …")
history = trainer.train(train_loader, val_loader)

with (outdir / "tcr_history.json").open("w") as fh:
    json.dump(history, fh, indent=2)

# ── Test evaluation ─────────────────────────────────────────────────────
model.load_state_dict(torch.load(outdir / "tcr_model.pt", map_location=trainer.device))
test_metrics = trainer.evaluate(test_loader)
logger.info("Test metrics: %s", test_metrics)

# ── Predictions + saliency ───────────────────────────────────────────────
all_loader = DataLoader(ds, batch_size=1)
donor_ids  = ds.donors
preds, pre_mils = [], []

model.eval()
with torch.no_grad():
    for i in range(len(ds)):
        x, y = ds[i]
        x = x.unsqueeze(0).to(trainer.device)
        p, pre = model(x)
        preds.append(p.cpu().numpy())
        pre_mils.append(pre.cpu().numpy())

import numpy as np
preds    = np.concatenate(preds)
pre_mils = np.concatenate(pre_mils)

# Export predictions
results_df = pd.DataFrame({
    "donor": donor_ids,
    "prob_class1": preds[:, 1] if preds.ndim > 1 else preds,
})
results_df.to_csv(outdir / "tcr_predictions.csv", index=False)

# Export per-TCR importance (pre_mil score)
# Group importance scores back to donor bags
importance_rows = []
for i, donor in enumerate(donor_ids):
    bag_scores = pre_mils[i]  # (n_tcrs,)
    top_idx   = np.argsort(bag_scores)[::-1][:10]  # top-10 most important TCRs
    for rank, tcr_idx in enumerate(top_idx):
        importance_rows.append({
            "donor": donor,
            "tcr_rank": rank + 1,
            "importance_score": bag_scores[tcr_idx],
        })

importance_df = pd.DataFrame(importance_rows)
importance_df.to_csv(outdir / "tcr_importance.csv", index=False)

logger.info("TCR MIL complete. Outputs in %s", outdir)
