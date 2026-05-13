#!/usr/bin/env python3
import os
os.environ["NUMBA_DISABLE_JIT"] = "1"
"""
Standalone TCR-epitope binding model trainer.

Downloads TCREpitopeBinding benchmark data via tdc.multi_pred,
embeds all sequences with ESM-2, concatenates epitope_emb + tcr_emb,
fits StandardScaler per split, trains XGBClassifier, and saves:
  xgboost_model.pkl, scaler.pkl, epitopes.fasta, training_history.json, run_params.json

Usage:
    python scripts/train_tcr_epitope_binding.py --output-dir tcr_epitope_models/ --local-gpu

Options:
    --output-dir      Output directory (default: tcr_epitope_models/)
    --esm2-model      ESM-2 model name (default: esm2_t6_8M_UR50D)
    --tdc-cache-dir   TDC cache directory (default: /tmp/tdc_cache/)
    --local-gpu       Use GPU acceleration if available (default: CPU if absent)
"""

import argparse
import json
import logging
import os
import pickle
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import torch

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger("train_tcr_epitope_binding")


# ── ESM-2 embedding helper ──────────────────────────────────────────────────────

def embed_sequences(model, tokenizer, sequences, device, batch_size=32):
    """
    Embed amino-acid sequences using ESM-2.
    Mean-pools last_hidden_state[:, 1:-1, :] to get one vector per sequence.
    """
    model.eval()
    embeddings = []

    for start in range(0, len(sequences), batch_size):
        batch = sequences[start : start + batch_size]
        batch = [s if (s and s != "NA") else "X" for s in batch]

        inputs = tokenizer(batch, return_tensors="pt", padding=True, truncation=True, max_length=128)
        inputs = {k: v.to(device) for k, v in inputs.items()}

        with torch.no_grad():
            outputs = model(**inputs)

        seq_embeds = outputs.last_hidden_state[:, 1:-1, :].mean(dim=1)
        embeddings.append(seq_embeds.cpu().numpy())

    return np.vstack(embeddings)


# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Train TCR-epitope binding model")
    parser.add_argument(
        "--output-dir",
        type=str,
        default="tcr_epitope_models/",
        help="Output directory (default: tcr_epitope_models/)",
    )
    parser.add_argument(
        "--esm2-model",
        type=str,
        default="esm2_t6_8M_UR50D",
        help="ESM-2 model name (default: esm2_t6_8M_UR50D)",
    )
    parser.add_argument(
        "--tdc-cache-dir",
        type=str,
        default="/tmp/tdc_cache/",
        help="TDC cache directory (default: /tmp/tdc_cache/)",
    )
    parser.add_argument(
        "--local-gpu",
        action="store_true",
        help="Use GPU acceleration (default: False = use CPU)",
    )
    args = parser.parse_args()

    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    tdc_cache_dir = Path(args.tdc_cache_dir).resolve()
    tdc_cache_dir.mkdir(parents=True, exist_ok=True)

    logger.info("Output directory: %s", output_dir)
    logger.info("ESM-2 model: %s", args.esm2_model)

    # ── Device ──────────────────────────────────────────────────────────────────
    use_gpu = args.local_gpu and torch.cuda.is_available()
    device = torch.device("cuda" if use_gpu else "cpu")
    logger.info("PyTorch device: %s", device)

    # ── Install tdc if needed ──────────────────────────────────────────────────
    try:
        import tdc
    except ImportError:
        logger.info("Installing tdc …")
        os.system(f"{sys.executable} -m pip install tdc -q")
        import tdc

    from tdc.multi_pred import TCREpitopeBinding

    # ── Load dataset ─────────────────────────────────────────────────────────────
    logger.info("Loading TCREpitopeBinding (weber) dataset from TDC …")
    data = TCREpitopeBinding(name="weber", path=str(tdc_cache_dir))

    logger.info("Computing random split (seed=816, frac=[0.7, 0.1, 0.2]) …")
    split = data.get_split(method="random", seed=816, frac=[0.7, 0.1, 0.2])

    train_df = split["train"]
    val_df = split["val"]
    test_df = split["test"]

    logger.info(
        "Splits — train: %d, val: %d, test: %d",
        len(train_df), len(val_df), len(test_df),
    )

    # Collect all unique sequences across splits
    all_seqs = {}
    for df in [train_df, val_df, test_df]:
        for _, row in df.iterrows():
            epitope = str(row["epitope_aa"])
            tcr = str(row["tcr_aa"])
            if epitope not in all_seqs:
                all_seqs[epitope] = ("epitope", epitope)
            if tcr not in all_seqs:
                all_seqs[tcr] = ("tcr", tcr)

    epitope_seqs = [v[1] for v in all_seqs.values() if v[0] == "epitope"]
    tcr_seqs = [v[1] for v in all_seqs.values() if v[0] == "tcr"]
    logger.info("Unique epitopes: %d, unique TCRs: %d", len(epitope_seqs), len(tcr_seqs))

    # ── Load ESM-2 model ─────────────────────────────────────────────────────────
    full_model_name = f"facebook/{args.esm2_model}" if not args.esm2_model.startswith("facebook/") else args.esm2_model
    logger.info("Loading ESM-2 model: %s", full_model_name)

    from transformers import AutoModel, AutoTokenizer

    tokenizer = AutoTokenizer.from_pretrained(full_model_name)
    model = AutoModel.from_pretrained(full_model_name)
    model = model.to(device)

    embedding_dim = model.config.hidden_size
    logger.info("ESM-2 embedding dimension: %d", embedding_dim)

    # ── Embed all sequences ──────────────────────────────────────────────────────
    logger.info("Embedding %d epitope sequences …", len(epitope_seqs))
    epitope_embs = embed_sequences(model, tokenizer, epitope_seqs, device)
    epitope_emb_dict = {seq: epitope_embs[i] for i, seq in enumerate(epitope_seqs)}

    logger.info("Embedding %d TCR sequences …", len(tcr_seqs))
    tcr_embs = embed_sequences(model, tokenizer, tcr_seqs, device)
    tcr_emb_dict = {seq: tcr_embs[i] for i, seq in enumerate(tcr_seqs)}

    # ── Build feature matrices (concat epitope_emb + tcr_emb) ───────────────────
    logger.info("Building concat feature matrices (2 × %d = %d dim) …", embedding_dim, 2 * embedding_dim)

    def build_X(df):
        rows = []
        for _, row in df.iterrows():
            e_emb = epitope_emb_dict[str(row["epitope_aa"])]
            t_emb = tcr_emb_dict[str(row["tcr_aa"])]
            rows.append(np.concatenate([e_emb, t_emb]))
        return np.array(rows)

    X_train = build_X(train_df)
    X_val = build_X(val_df)
    X_test = build_X(test_df)

    y_train = train_df["label"].values
    y_val = val_df["label"].values
    y_test = test_df["label"].values

    logger.info(
        "Train: %s, Val: %s, Test: %s",
        X_train.shape, X_val.shape, X_test.shape,
    )

    # ── Fit StandardScaler ───────────────────────────────────────────────────────
    logger.info("Fitting StandardScaler on training set …")
    from sklearn.preprocessing import StandardScaler

    scaler = StandardScaler()
    scaler.fit(X_train.tolist())

    X_train_scaled = scaler.transform(X_train)
    X_val_scaled = scaler.transform(X_val)
    X_test_scaled = scaler.transform(X_test)

    # ── Train XGBoost ───────────────────────────────────────────────────────────
    tree_method = "gpu_hist" if use_gpu else "hist"
    logger.info("Training XGBClassifier(tree_method=%s, random_state=816) …", tree_method)

    from xgboost import XGBClassifier

    clf = XGBClassifier(
        tree_method=tree_method,
        random_state=816,
        eval_metric="logloss",
        early_stopping_rounds=20,
        n_estimators=500,
    )
    clf.fit(
        X_train_scaled, y_train,
        eval_set=[(X_val_scaled, y_val)],
        verbose=20,
    )

    # ── Evaluate ─────────────────────────────────────────────────────────────────
    train_acc = clf.score(X_train_scaled, y_train)
    val_acc = clf.score(X_val_scaled, y_val)
    test_acc = clf.score(X_test_scaled, y_test)

    logger.info("Train accuracy: %.4f", train_acc)
    logger.info("Val accuracy:   %.4f", val_acc)
    logger.info("Test accuracy:  %.4f", test_acc)

    # ── Save model + scaler ──────────────────────────────────────────────────────
    model_path = output_dir / "xgboost_model.pkl"
    scaler_path = output_dir / "scaler.pkl"

    logger.info("Saving XGBoost model: %s", model_path)
    with open(model_path, "wb") as f:
        pickle.dump(clf, f)

    logger.info("Saving StandardScaler: %s", scaler_path)
    with open(scaler_path, "wb") as f:
        pickle.dump(scaler, f)

    # ── Save epitopes.fasta ──────────────────────────────────────────────────────
    unique_epitopes = []
    for df in [train_df, val_df, test_df]:
        for epi in df["epitope_aa"].unique():
            if epi not in unique_epitopes:
                unique_epitopes.append(epi)

    fasta_path = output_dir / "epitopes.fasta"
    logger.info("Writing %d unique epitopes to %s", len(unique_epitopes), fasta_path)
    with open(fasta_path, "w") as f:
        for i, seq in enumerate(unique_epitopes):
            f.write(f">epitope_{i:04d}\n{seq}\n")

    # ── Save training_history.json ───────────────────────────────────────────────
    history = {
        "n_train": int(len(train_df)),
        "n_val": int(len(val_df)),
        "n_test": int(len(test_df)),
        "train_acc": float(train_acc),
        "val_acc": float(val_acc),
        "test_acc": float(test_acc),
        "model_name": "XGBClassifier",
        "embedding_dim": int(2 * embedding_dim),
        "esm2_model": full_model_name,
        "n_estimators": clf.n_estimators if hasattr(clf, "n_estimators") else None,
        "best_iteration": clf.best_iteration if hasattr(clf, "best_iteration") else None,
    }

    history_path = output_dir / "training_history.json"
    logger.info("Saving training history: %s", history_path)
    with open(history_path, "w") as f:
        json.dump(history, f, indent=2)

    # ── Save run_params.json ─────────────────────────────────────────────────────
    run_params = {
        "esm2_model_name": full_model_name,
        "esm2_embedding_dim": int(embedding_dim),
        "concat_dim": int(2 * embedding_dim),
        "tdc_dataset": "weber",
        "split_seed": 816,
        "split_frac": [0.7, 0.1, 0.2],
        "use_gpu": bool(use_gpu),
        "tree_method": tree_method,
        "output_dir": str(output_dir),
    }

    run_params_path = output_dir / "run_params.json"
    with open(run_params_path, "w") as f:
        json.dump(run_params, f, indent=2)

    logger.info("Complete. Outputs in: %s", output_dir)
    for fname in ["xgboost_model.pkl", "scaler.pkl", "epitopes.fasta",
                  "training_history.json", "run_params.json"]:
        fpath = output_dir / fname
        size = fpath.stat().st_size if fpath.exists() else 0
        logger.info("  %s  (%d bytes)", fname, size)


if __name__ == "__main__":
    main()