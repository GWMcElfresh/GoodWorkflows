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

# Inputs are already staged in the work directory by Nextflow.
# ${merged_h5ad} and ${genes_file} are Nextflow template variables (input paths).
nmfvae-train \
    --input "${merged_h5ad}" \
    --output . \
    --genes-file "${genes_file}" \
    --latent-dim "${params.nmf_vae_latent_dim}" \
    --epochs "${params.nmf_vae_epochs}" \
    --batch-size "${params.nmf_vae_batch_size}" \
    --lr "${params.nmf_vae_lr}" \
    --lambda-graph "${lambda_graph}" \
    --fetch-archs4 \
    --archs4-cache-path "${params.nmf_vae_archs4_pkl}" \
    --save-checkpoint \
    --save-laplacian graph \
    --species-id "${params.nmf_vae_species_id}"

  # Validate expected outputs exist
  for out_file in latent_Z.csv decoder_W.csv loss_history.csv loss.png model_checkpoint.pt; do
      if [ ! -f "\$out_file" ]; then
          echo "ERROR: Expected output '\$out_file' was not created by nmfvae-train." >&2
          exit 1
      fi
  done

echo "NMF_VAE_FACTORIZE complete."
