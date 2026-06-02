# TCR Epitope Pipeline

`--workflow tcr_epitope`

Ingests Seurat objects with TCR metadata, quantifies TCR clones via tcrClustR, embeds clone CDR3 sequences with ESM-2, predicts per-peptide binding scores for each sample's epitope pool, and joins clone-level results back into the original Seurat object. GPU required.

**Input requirement:** Samplesheet must include an `epitope_file` column pointing to a per-sample FASTA of peptide epitopes.

---

## Stage-by-stage dataflow

| Stage | Module | Input | Output | Compute |
|---|---|---|---|---|
| INGEST | `rdiscvr/ingest_*` | LabKey / URL / local file | `{sample_id}.rds` | CPU |
| QUANTIFY_TCR | `mil_ton/quantify_tcr` | Seurat RDS (with TRA/TRB columns) | `{sample_id}_tcr.rds`, `{sample_id}_tcr_metadata.csv` | CPU |
| MERGE_TCR_METADATA | `mil_ton/merge_tcr_metadata` | Collected TCR CSVs | `merged_tcr_metadata.csv` | CPU |
| EMBED_CLONES | `tcr_epitope/embed` | `merged_tcr_metadata.csv` + epitope FASTA | `clone_embeddings.parquet` (320-dim ESM-2 per clone) | GPU |
| TCR_UMAP | `tcr_epitope/tcr_umap` | Clone embeddings | `clone_metadata.parquet` (UMAP coords, Leiden clusters) | GPU |
| PREDICT_BINDING | `tcr_epitope/predict_binding` | Clone embeddings + per-sample epitope FASTA + binding model | Per-sample `{sample_id}_binding_scores.parquet`, `{sample_id}_cell_binding_scores.parquet` | GPU |
| JOIN_SEURAT | `tcr_epitope/join_seurat` | Seurat RDS + clone metadata + binding scores | `{sample_id}_annotated.rds` with TCR UMAP/cluster/binding columns | CPU |

---

## Container images

- `ghcr.io/bimberlabinternal/tcrclustr:latest` — tcrClustR quantification
- `ghcr.io/gwmcelfresh/mil-ton:latest` — ESM-2 embedding, UMAP, binding prediction, Seurat join

---

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `--esm2_model_name` | `facebook/esm2_t6_8M_UR50D` | ESM-2 model for clone embedding (320-dim) |
| `--binding_model_path` | _(required)_ | Path to pre-trained binding prediction model (XGBoost or similar) |
| `--tcr_umap_resolution` | `1.0` | Leiden resolution for clone clustering |
| `--tcr_embedding_dim` | `320` | Embedding dimension (fixed for esm2_t6_8M) |

---

## Outputs

`outputs/tcr_epitope/`:

| File | Description |
|---|---|
| `clone_embeddings.parquet` | Per-clone ESM-2 320-dim embeddings |
| `{sample_id}_binding_scores.parquet` | Clone × peptide binding scores per sample |
| `{sample_id}_cell_binding_scores.parquet` | Cell-level binding scores per sample |
| `clone_metadata.parquet` | Clone UMAP + Leiden cluster assignments |
| `{sample_id}_annotated.rds` | Original Seurat RDS + TCR columns joined |

---

## Running locally

```bash
bash template/gw/run.sh --workflow tcr_epitope --input tcr_epitope_samplesheet.csv --binding_model_path tcr_epitope_models
```

Requires a pre-trained binding model. The sample-specific `epitope_file` column in the samplesheet defines which peptide pool each sample was stimulated with.

For the generated code-level reference, see [API Reference → Workflows](../api/generated/workflows.md#tcr-epitope-pipeline).
