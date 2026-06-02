# NMF-VAE Factorization

`--workflow nmf_vae`

Ingests Seurat objects, exports 10x-like count matrices, merges per-sample counts into a joint expression matrix, and factorizes with NMF-VAE to extract metagenic programs. GPU required for `NMF_VAE_FACTORIZE`; `NMF_VAE_MERGE_COUNTS` is CPU.

---

## Stage-by-stage dataflow

| Stage | Module | Input | Output | Compute |
|---|---|---|---|---|
| INGEST | `rdiscvr/ingest_*` | LabKey / URL / local file | `{sample_id}.rds` | CPU |
| EXPORT_COUNTS | `cellmembrane/seurat` | Seurat RDS | `{sample_id}_counts/` (matrix.mtx, features.tsv, barcodes.tsv, obs_meta.csv) | CPU |
| NMF_VAE_MERGE_COUNTS | `nmf_vae/merge_counts` | Collected count directories | `merged_gex.h5ad` — cell x gene AnnData with `lam_graph` | CPU |
| NMF_VAE_FACTORIZE | `nmf_vae/factorize` | `merged_gex.h5ad` | `latent_Z.csv` (cell embeddings), `decoder_W.csv` (gene loadings), `loss_history.csv`, `model_checkpoint.pt` | GPU |

---

## Container images

- `ghcr.io/gwmcelfresh/nmf-vae:latest` — contains NMF-VAE training code + dependencies
- `.archs4/` host directory is mounted for ARCHS4 correlation cache (6 GB pickle)

---

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `--nmf_vae_latent_dim` | `50` | Latent dimension (k) for factorization |
| `--nmf_vae_epochs` | `200` | Number of training epochs |
| `--nmf_vae_lambda_graph` | `'moderate'` | Laplacian graph regularization strength |
| `--nmf_vae_archs4_cache` | `$PWD/.archs4` | ARCHS4 correlation cache directory (bind-mounted) |

---

## Outputs

`outputs/nmf_vae/`:

| File | Description |
|---|---|
| `latent_Z.csv` | Cell-level NMF-VAE embeddings (cells × latent_dim) |
| `decoder_W.csv` | Gene-level factor loadings (genes × latent_dim) |
| `loss_history.csv` | Training loss per epoch |
| `model_checkpoint.pt` | PyTorch model checkpoint |

---

## Running locally

```bash
bash template/gw/run.sh --workflow nmf_vae --input nmf_vae_samplesheet.csv
```

Uses the `local_gpu` profile (Podman + GPU passthrough). For stub validation:

```bash
nextflow run main.nf -stub-run -profile test --workflow nmf_vae --input /tmp/nmf_vae_samplesheet.csv
```

For the generated code-level reference, see [API Reference → Workflows](../api/generated/workflows.md#nmf-vae-pipeline).
