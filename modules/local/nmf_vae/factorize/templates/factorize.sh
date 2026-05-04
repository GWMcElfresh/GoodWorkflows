#!/usr/bin/env bash
# Nextflow template: factorize.sh
# NMF-VAE factorization via nmfvae-train on a joint count matrix.
#
# Nextflow substitutions (resolved before bash runs):
#   ${merged_h5ad}                – path to merged_counts.h5ad
#   ${genes_file}                 – path to genes.txt
#   ${lambda_graph}               – per-sample lambda-graph override from samplesheet
#   ${params.nmf_vae_latent_dim}  – latent dimension
#   ${params.nmf_vae_epochs}      – number of training epochs
#   ${params.nmf_vae_batch_size}  – training batch size
#   ${params.nmf_vae_lr}          – learning rate
#   ${params.nmf_vae_archs4_cache}– path to Arches4 cache directory
#   ${params.nmf_vae_species_id}  – species identifier

set -euo pipefail

# Copy inputs to well-known names in the work directory
cp "${merged_h5ad}" merged_counts.h5ad
cp "${genes_file}" genes.txt

nmfvae-train \
    --input merged_counts.h5ad \
    --output . \
    --genes-file genes.txt \
    --latent-dim "${params.nmf_vae_latent_dim}" \
    --epochs "${params.nmf_vae_epochs}" \
    --batch-size "${params.nmf_vae_batch_size}" \
    --lr "${params.nmf_vae_lr}" \
    --lambda-graph "${lambda_graph}" \
    --fetch-archs4 \
    --archs4-cache-path "${params.nmf_vae_archs4_cache}" \
    --save-checkpoint \
    --save-laplacian . \
    --species-id "${params.nmf_vae_species_id}"

# Validate expected outputs exist
for f in latent_Z.csv decoder_W.csv loss_history.csv loss.png model_checkpoint.pt; do
    if [ ! -f "$f" ]; then
        echo "ERROR: Expected output '$f' was not created by nmfvae-train." >&2
        exit 1
    fi
done

echo "NMF_VAE_FACTORIZE complete."
