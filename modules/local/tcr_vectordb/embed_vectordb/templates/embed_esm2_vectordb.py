#!/usr/bin/env python3
# NUMBA_DISABLE_JIT=1
"""
Nextflow template: embed_esm2_vectordb.py

EMBED_TCR_VECTORDATABASE — run ESM-2 embeddings for TRA/TRB sequences and
write parquet vector database shards plus a persisted nearest-neighbor index.

Inputs:
  - sequences_csv: extracted long CSV from EXTRACT_TCR_SEQUENCES

Outputs (written into vectordb_out/ and published via Nextflow publishDir):
  - {cDNA_ID}_single.parquet
  - {cDNA_ID}_paired.parquet
  - {cDNA_ID}_single_index.faiss + {cDNA_ID}_single_index_meta.json
  - {cDNA_ID}_paired_index.faiss + {cDNA_ID}_paired_index_meta.json
"""

import os
from pathlib import Path

import numpy as np
import pandas as pd
import torch
from transformers import AutoModel, AutoTokenizer

from mil_ton.vectordb.faiss_index import build_flat_cosine_index, write_index_bundle

# ── Nextflow template variables ──────────────────────────────────────────────
sequences_csv = Path("${sequences_csv}").resolve()
sample_id = "${meta.id}"

out_root = Path("${params.outdir}/tcr_vectordbs").resolve()
published_vectordb_dir = out_root / "vectordb_out"
work_vectordb_dir = Path("vectordb_out").resolve()

esm2_model_name = "${params.tcr_vectordb_esm2_model_name}"
max_length = int("${params.tcr_vectordb_max_length}")
batch_size = int("${params.tcr_vectordb_batch_size}")
knn_k = int("${params.tcr_vectordb_knn_k}")

hf_cache_dir = Path("${params.tcr_vectordb_hf_cache_dir}").resolve()
hf_cache_dir.mkdir(parents=True, exist_ok=True)

os.environ.setdefault("HF_HOME", str(hf_cache_dir))
os.environ.setdefault("TRANSFORMERS_CACHE", str(hf_cache_dir))

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")


def to_upper_str(x):
    if x is None or (isinstance(x, float) and np.isnan(x)):
        return ""
    return str(x).upper()


def masked_mean_last_hidden(outputs, attention_mask):
    """
    Pool token embeddings with attention_mask, skipping the first token
    (<cls>). This avoids padded tokens skewing the mean.
    """
    hidden = outputs.last_hidden_state  # (b, seq_len, hidden)
    # Skip <cls> at position 0, keep remaining tokens aligned to attention_mask[:,1:]
    hidden_tokens = hidden[:, 1:, :]
    mask_tokens = attention_mask[:, 1:].unsqueeze(-1).to(hidden_tokens.dtype)
    summed = (hidden_tokens * mask_tokens).sum(dim=1)
    denom = mask_tokens.sum(dim=1).clamp(min=1.0)
    return (summed / denom).detach()


def embed_texts(model, tokenizer, texts, *, max_length, batch_size, device):
    if len(texts) == 0:
        return np.zeros((0, int(model.config.hidden_size)), dtype=np.float32)

    model.eval()
    embeddings = []
    with torch.no_grad():
        for i in range(0, len(texts), batch_size):
            batch = texts[i : i + batch_size]
            inputs = tokenizer(
                batch,
                return_tensors="pt",
                padding=True,
                truncation=True,
                max_length=max_length,
            )
            inputs = {k: v.to(device) for k, v in inputs.items()}
            outputs = model(**inputs)
            pooled = masked_mean_last_hidden(outputs, inputs["attention_mask"])
            embeddings.append(pooled.float().cpu().numpy())
    return np.concatenate(embeddings, axis=0)


def copy_if_exists(src: Path, dst: Path):
    if src.exists():
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(src.read_bytes())
        return True
    return False


def main():
    work_vectordb_dir.mkdir(parents=True, exist_ok=True)

    if not sequences_csv.exists():
        # Stub-run can create empty CSV; treat as empty dataset.
        df = pd.DataFrame(columns=["cDNA_ID", "SubjectId", "barcode", "chain", "sequence", "sequence_index", "v_gene", "j_gene"])
    else:
        df = pd.read_csv(sequences_csv)

    # Normalize empties
    if df.shape[0] == 0:
        # Write empty outputs for the stubbed sample_id.
        cdna_ids = [sample_id]
    else:
        cdna_ids = sorted(df["cDNA_ID"].dropna().astype(str).unique().tolist())

    if len(cdna_ids) == 0:
        cdna_ids = [sample_id]

    # Load ESM-2 once.
    print(f"[EMBED_TCR_VECTORDATABASE] Loading ESM-2 model: {esm2_model_name} on {device}")
    tokenizer = AutoTokenizer.from_pretrained(esm2_model_name)
    model = AutoModel.from_pretrained(esm2_model_name).to(device)

    hidden_size = int(model.config.hidden_size)
    print(f"[EMBED_TCR_VECTORDATABASE] hidden_size={hidden_size}, model={esm2_model_name}")

    # Pre-normalize gene columns for conflict dropping.
    if "v_gene" not in df.columns:
        df["v_gene"] = ""
    if "j_gene" not in df.columns:
        df["j_gene"] = ""

    df["v_gene_norm"] = df["v_gene"].map(to_upper_str)
    df["j_gene_norm"] = df["j_gene"].map(to_upper_str)
    df["chain"] = df["chain"].astype(str)
    df["sequence"] = df["sequence"].astype(str)
    df["sequence_index"] = df["sequence_index"].fillna(-1).astype(int)

    # Drop rows where v/j genes conflict with chain assignment (Rdiscvr-style).
    is_TRA = df["chain"] == "TRA"
    is_TRB = df["chain"] == "TRB"

    drop_TRA = is_TRA & (
        df["v_gene_norm"].str.contains(r"(BV|GV)", regex=True, na=False)
        | df["j_gene_norm"].str.contains(r"(BJ|GJ)", regex=True, na=False)
    )
    drop_TRB = is_TRB & (
        df["v_gene_norm"].str.contains(r"(AV|DV)", regex=True, na=False)
        | df["j_gene_norm"].str.contains(r"(AJ|DJ)", regex=True, na=False)
    )
    df_filtered = df[~(drop_TRA | drop_TRB)].copy()

    # Process each cDNA_ID shard.
    for cdna_id in cdna_ids:
        single_path = work_vectordb_dir / f"{cdna_id}_single.parquet"
        paired_path = work_vectordb_dir / f"{cdna_id}_paired.parquet"
        single_index_path = work_vectordb_dir / f"{cdna_id}_single_index.faiss"
        single_meta_path = work_vectordb_dir / f"{cdna_id}_single_index_meta.json"
        paired_index_path = work_vectordb_dir / f"{cdna_id}_paired_index.faiss"
        paired_meta_path = work_vectordb_dir / f"{cdna_id}_paired_index_meta.json"

        # Resume: if published files already exist, copy them into the work outputs.
        pub_single = published_vectordb_dir / f"{cdna_id}_single.parquet"
        pub_paired = published_vectordb_dir / f"{cdna_id}_paired.parquet"
        pub_single_idx = published_vectordb_dir / f"{cdna_id}_single_index.faiss"
        pub_single_meta = published_vectordb_dir / f"{cdna_id}_single_index_meta.json"
        pub_paired_idx = published_vectordb_dir / f"{cdna_id}_paired_index.faiss"
        pub_paired_meta = published_vectordb_dir / f"{cdna_id}_paired_index_meta.json"

        if copy_if_exists(pub_single, single_path):
            pass
        if copy_if_exists(pub_paired, paired_path):
            pass
        if copy_if_exists(pub_single_idx, single_index_path):
            pass
        if copy_if_exists(pub_single_meta, single_meta_path):
            pass
        if copy_if_exists(pub_paired_idx, paired_index_path):
            pass
        if copy_if_exists(pub_paired_meta, paired_meta_path):
            pass

        # If both parquets exist, skip embedding for this shard.
        if single_path.exists() and paired_path.exists():
            print(f"[EMBED_TCR_VECTORDATABASE] Skip (resume hit): {cdna_id}")
            continue

        shard = df_filtered[df_filtered["cDNA_ID"].astype(str) == str(cdna_id)].copy()
        if shard.shape[0] == 0:
            # Empty shard: still write empty outputs and empty index metadata.
            empty_single = pd.DataFrame(columns=[
                "cDNA_ID", "SubjectId", "barcode", "chain", "sequence", "sequence_index", "esm2_model", "embedding"
            ])
            empty_single.to_parquet(single_path, index=False)
            empty_paired = empty_single.copy()
            empty_paired["chain"] = "paired"
            empty_paired.to_parquet(paired_path, index=False)

            write_index_bundle(
                None, [], index_path=single_index_path, meta_path=single_meta_path, dim=hidden_size
            )
            write_index_bundle(
                None, [], index_path=paired_index_path, meta_path=paired_meta_path, dim=hidden_size
            )
            continue

        # ── Single-chain parquet ───────────────────────────────────────────
        single_cols = ["cDNA_ID", "SubjectId", "barcode", "chain", "sequence", "sequence_index"]
        shard_single = shard[single_cols].copy()
        shard_single["esm2_model"] = esm2_model_name

        unique_single = shard_single[["chain", "sequence"]].drop_duplicates()
        unique_seqs = unique_single["sequence"].tolist()
        unique_emb = embed_texts(
            model, tokenizer, unique_seqs,
            max_length=max_length,
            batch_size=batch_size,
            device=device,
        )
        seq_to_emb = {seq: unique_emb[i] for i, seq in enumerate(unique_seqs)}
        shard_single["embedding"] = shard_single["sequence"].map(lambda s: seq_to_emb[str(s)].tolist())

        shard_single.to_parquet(single_path, index=False)

        # Index on unique sequences per chain (FAISS, cosine via L2-normalized inner product).
        items = [
            {"chain": unique_single.iloc[i]["chain"], "sequence": unique_single.iloc[i]["sequence"]}
            for i in range(len(unique_single))
        ]
        single_faiss = build_flat_cosine_index(unique_emb) if unique_emb.shape[0] > 0 else None
        write_index_bundle(
            single_faiss,
            items,
            index_path=single_index_path,
            meta_path=single_meta_path,
            dim=hidden_size,
        )

        # ── Paired-chain parquet ───────────────────────────────────────────
        df_TRA = shard[shard["chain"] == "TRA"].copy()
        df_TRB = shard[shard["chain"] == "TRB"].copy()

        if df_TRA.shape[0] == 0 or df_TRB.shape[0] == 0:
            empty_paired = pd.DataFrame(columns=[
                "cDNA_ID", "SubjectId", "barcode", "chain", "sequence", "sequence_index", "esm2_model", "embedding"
            ])
            empty_paired.to_parquet(paired_path, index=False)
            write_index_bundle(
                None, [], index_path=paired_index_path, meta_path=paired_meta_path, dim=hidden_size
            )
            continue

        paired = df_TRA.merge(
            df_TRB,
            on=["cDNA_ID", "SubjectId", "barcode", "sequence_index"],
            suffixes=("_TRA", "_TRB"),
        )

        if paired.shape[0] == 0:
            empty_paired = pd.DataFrame(columns=[
                "cDNA_ID", "SubjectId", "barcode", "chain", "sequence", "sequence_index", "esm2_model", "embedding"
            ])
            empty_paired.to_parquet(paired_path, index=False)
            write_index_bundle(
                None, [], index_path=paired_index_path, meta_path=paired_meta_path, dim=hidden_size
            )
            continue

        paired["paired_sequence"] = paired["sequence_TRA"].astype(str) + ":" + paired["sequence_TRB"].astype(str)

        unique_paired = paired[["paired_sequence"]].drop_duplicates()
        paired_seqs = unique_paired["paired_sequence"].tolist()
        paired_emb = embed_texts(
            model, tokenizer, paired_seqs,
            max_length=max_length,
            batch_size=batch_size,
            device=device,
        )
        paired_seq_to_emb = {seq: paired_emb[i] for i, seq in enumerate(paired_seqs)}

        out_paired = pd.DataFrame({
            "cDNA_ID": paired["cDNA_ID"].astype(str).values,
            "SubjectId": paired["SubjectId"].astype(str).values,
            "barcode": paired["barcode"].astype(str).values,
            "chain": np.array(["paired"] * paired.shape[0]),
            "sequence": paired["paired_sequence"].astype(str).values,
            "sequence_index": paired["sequence_index"].astype(int).values,
            "esm2_model": esm2_model_name,
        })
        out_paired["embedding"] = out_paired["sequence"].map(lambda s: paired_seq_to_emb[str(s)].tolist())
        out_paired.to_parquet(paired_path, index=False)

        # Paired index on unique paired sequences.
        items_p = [{"sequence": paired_seqs[i]} for i in range(len(paired_seqs))]
        paired_faiss = build_flat_cosine_index(paired_emb) if paired_emb.shape[0] > 0 else None
        write_index_bundle(
            paired_faiss,
            items_p,
            index_path=paired_index_path,
            meta_path=paired_meta_path,
            dim=hidden_size,
        )

        print(f"[EMBED_TCR_VECTORDATABASE] Wrote: {cdna_id} single/paired parquet + indices")


if __name__ == "__main__":
    main()

