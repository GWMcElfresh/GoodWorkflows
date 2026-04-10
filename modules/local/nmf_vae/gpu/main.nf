/*
 * modules/local/nmf_vae/gpu/main.nf
 *
 * Process: GPU_ANALYSIS
 * Container: ghcr.io/gwmcelfresh/nmf-vae:latest
 * Label: process_gpu  (4 CPUs, 32 GB RAM, 1 GPU, 24 h, partition=batch, qos=gpu)
 *
 * Purpose:
 *   Receive the h5ad files from ALL samples (collected into a single channel
 *   emission by main.nf), concatenate them into one cohort AnnData object,
 *   and run the NMF-VAE model with GPU-accelerated minibatch training.
 *
 *   This is intentionally a single SLURM job (not per-sample) because:
 *     a) GPU queue wait-times are long; batching minimises scheduler overhead.
 *     b) The VAE needs cross-sample variation to learn a meaningful latent
 *        space; training per-sample would defeat the model's purpose.
 *
 * Inputs:
 *   path(h5ad_files)  – list of h5ad files staged into the work directory.
 *                       Nextflow stages each file as <sample_id>.h5ad so they
 *                       are accessible by globbing *.h5ad in the script.
 *
 * Outputs:
 *   path("model_outputs/"), emit: model
 *     Directory containing:
 *       model_outputs/
 *         nmf_vae_weights.pt       – trained PyTorch model weights
 *         latent_embeddings.h5ad   – cohort AnnData with latent coordinates in .obsm
 *         training_history.csv     – loss per epoch
 *         gpu_info.txt             – nvidia-smi snapshot at job start
 *
 * GPU note:
 *   The beforeScript in nextflow.config sets --qos=gpu and --gres=gpu:1 via
 *   clusterOptions.  CUDA is expected to be available inside the container
 *   at the standard /dev/nvidia* device paths; --security-opt label=disable
 *   (already in podman.runOptions) is required for GPU passthrough on most
 *   SELinux-enabled HPC nodes.
 */

process GPU_ANALYSIS {
    label 'process_gpu'

    container 'ghcr.io/gwmcelfresh/nmf-vae:latest'

    publishDir "${params.outdir}/gpu", mode: 'copy'

    input:
    path h5ad_files   // list of all *.h5ad files staged into work dir

    output:
    path 'model_outputs/', emit: model

    stub:
    """
    mkdir -p model_outputs
    touch model_outputs/nmf_vae_weights.pt
    touch model_outputs/latent_embeddings.h5ad
    touch model_outputs/training_history.csv
    touch model_outputs/gpu_info.txt
    """

    script:
    // Python is run via a single-quoted bash heredoc so that Python backslash
    // escapes and format-string braces are not processed by Groovy's string
    // interpolation engine.  Nextflow variables (${task.*}, ${params.*}) must
    // be resolved in the outer bash layer before the heredoc delimiter.
    """
    python3 - << 'NF_PYEOF'
    import os
    import sys
    import glob
    import math
    import subprocess
    import pathlib

    import numpy  as np
    import pandas as pd
    import scanpy as sc
    import torch
    import torch.nn as nn
    from torch.utils.data import DataLoader, TensorDataset

    # -- Capture GPU info for diagnostics ------------------------------------
    out_dir = pathlib.Path("model_outputs")
    out_dir.mkdir(exist_ok=True)

    gpu_info_path = out_dir / "gpu_info.txt"
    try:
        result = subprocess.run(
            ["nvidia-smi"], capture_output=True, text=True, check=True
        )
        gpu_info_path.write_text(result.stdout)
        print(result.stdout)
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        msg = f"WARNING: nvidia-smi failed: {exc}\\n"
        gpu_info_path.write_text(msg)
        print(msg, file=sys.stderr)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"[GPU_ANALYSIS] Using device: {device}", flush=True)
    if device.type == "cuda":
        print(f"[GPU_ANALYSIS] GPU: {torch.cuda.get_device_name(0)}", flush=True)

    # -- Load and concatenate all h5ad files ---------------------------------
    h5ad_files = sorted(glob.glob("*.h5ad"))
    if not h5ad_files:
        raise RuntimeError("No *.h5ad files found in the work directory.")

    print(f"[GPU_ANALYSIS] Loading {len(h5ad_files)} sample(s):", flush=True)
    adatas = []
    for f in h5ad_files:
        print(f"  {f}", flush=True)
        adata = sc.read_h5ad(f)
        adatas.append(adata)

    cohort = sc.concat(adatas, label="sample", keys=[f.replace(".h5ad", "") for f in h5ad_files])
    print(f"[GPU_ANALYSIS] Cohort: {cohort.n_obs} cells x {cohort.n_vars} genes", flush=True)

    # -- Minimal pre-processing for model input ------------------------------
    # Ensure we work on raw counts (stored in cohort.raw if SeuratDisk exported them)
    if cohort.raw is not None:
        cohort = cohort.raw.to_adata()

    sc.pp.normalize_total(cohort, target_sum=1e4)
    sc.pp.log1p(cohort)
    sc.pp.highly_variable_genes(cohort, n_top_genes=3000, flavor="seurat_v3")
    cohort_hvg = cohort[:, cohort.var.highly_variable].copy()

    n_cells, n_genes = cohort_hvg.shape
    print(f"[GPU_ANALYSIS] HVG subset: {n_cells} cells x {n_genes} genes", flush=True)

    # -- NMF-VAE model definition --------------------------------------------
    # Adapt latent_dim, hidden_dim, and n_components to your biology.
    LATENT_DIM    = 32       # VAE latent space dimensionality
    N_COMPONENTS  = 20       # NMF components overlaid on the latent space
    HIDDEN_DIM    = 256
    N_EPOCHS      = 100
    BATCH_SIZE    = 512
    LEARNING_RATE = 1e-3

    class Encoder(nn.Module):
        def __init__(self, input_dim, hidden_dim, latent_dim):
            super().__init__()
            self.net = nn.Sequential(
                nn.Linear(input_dim, hidden_dim), nn.BatchNorm1d(hidden_dim), nn.ReLU(),
                nn.Linear(hidden_dim, hidden_dim), nn.BatchNorm1d(hidden_dim), nn.ReLU(),
            )
            self.mu      = nn.Linear(hidden_dim, latent_dim)
            self.log_var = nn.Linear(hidden_dim, latent_dim)

        def forward(self, x):
            h = self.net(x)
            return self.mu(h), self.log_var(h)

    class Decoder(nn.Module):
        def __init__(self, latent_dim, hidden_dim, output_dim):
            super().__init__()
            self.net = nn.Sequential(
                nn.Linear(latent_dim, hidden_dim), nn.BatchNorm1d(hidden_dim), nn.ReLU(),
                nn.Linear(hidden_dim, hidden_dim), nn.BatchNorm1d(hidden_dim), nn.ReLU(),
                nn.Linear(hidden_dim, output_dim), nn.Softplus(),
            )

        def forward(self, z):
            return self.net(z)

    class NmfVae(nn.Module):
        def __init__(self, input_dim, hidden_dim, latent_dim, n_components):
            super().__init__()
            self.encoder     = Encoder(input_dim, hidden_dim, latent_dim)
            self.decoder     = Decoder(latent_dim, hidden_dim, input_dim)
            # NMF dictionary matrix W (components x genes)
            self.nmf_W = nn.Parameter(
                torch.abs(torch.randn(n_components, input_dim)) * 0.01
            )

        def reparameterise(self, mu, log_var):
            std = torch.exp(0.5 * log_var)
            eps = torch.randn_like(std)
            return mu + eps * std

        def forward(self, x):
            mu, log_var = self.encoder(x)
            z           = self.reparameterise(mu, log_var)
            recon       = self.decoder(z)
            # NMF reconstruction via non-negative activations
            nmf_act  = torch.relu(z[:, :self.nmf_W.shape[0]])
            nmf_recon = nmf_act @ torch.relu(self.nmf_W)
            return recon, nmf_recon, mu, log_var

    def vae_loss(recon, nmf_recon, x, mu, log_var, beta=1.0, nmf_weight=0.5):
        # Reconstruction: mean squared error (use ZINB for count data in practice)
        recon_loss    = nn.functional.mse_loss(recon, x, reduction="mean")
        nmf_loss      = nn.functional.mse_loss(nmf_recon, x, reduction="mean")
        # KL divergence
        kl_divergence = -0.5 * torch.mean(1 + log_var - mu.pow(2) - log_var.exp())
        return recon_loss + nmf_weight * nmf_loss + beta * kl_divergence

    # -- Prepare data loader -------------------------------------------------
    if hasattr(cohort_hvg.X, "toarray"):
        X_np = cohort_hvg.X.toarray().astype(np.float32)
    else:
        X_np = np.asarray(cohort_hvg.X, dtype=np.float32)

    X_tensor = torch.from_numpy(X_np).to(device)
    dataset  = TensorDataset(X_tensor)
    loader   = DataLoader(dataset, batch_size=BATCH_SIZE, shuffle=True,
                          num_workers=min(4, os.cpu_count() or 1),
                          pin_memory=(device.type == "cuda"))

    # -- Initialise model and optimiser --------------------------------------
    model     = NmfVae(n_genes, HIDDEN_DIM, LATENT_DIM, N_COMPONENTS).to(device)
    optimiser = torch.optim.Adam(model.parameters(), lr=LEARNING_RATE)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimiser, T_max=N_EPOCHS)

    # -- Training loop -------------------------------------------------------
    history = []
    print("[GPU_ANALYSIS] Starting training ...", flush=True)
    for epoch in range(1, N_EPOCHS + 1):
        model.train()
        epoch_loss = 0.0
        for (batch,) in loader:
            optimiser.zero_grad()
            recon, nmf_recon, mu, log_var = model(batch)
            loss = vae_loss(recon, nmf_recon, batch, mu, log_var)
            loss.backward()
            optimiser.step()
            epoch_loss += loss.item() * batch.size(0)
        scheduler.step()
        avg_loss = epoch_loss / n_cells
        history.append({"epoch": epoch, "loss": avg_loss})
        if epoch % 10 == 0 or epoch == 1:
            print(f"[GPU_ANALYSIS] Epoch {epoch:4d}/{N_EPOCHS}  loss={avg_loss:.5f}", flush=True)

    # -- Save outputs --------------------------------------------------------
    # 1. Model weights
    weights_path = out_dir / "nmf_vae_weights.pt"
    torch.save(model.state_dict(), weights_path)
    print(f"[GPU_ANALYSIS] Saved weights: {weights_path}", flush=True)

    # 2. Latent embeddings
    model.eval()
    with torch.no_grad():
        mu_all, _ = model.encoder(X_tensor)
        z_all     = mu_all.cpu().numpy()

    cohort_hvg.obsm["X_nmfvae"] = z_all
    out_h5ad = out_dir / "latent_embeddings.h5ad"
    cohort_hvg.write_h5ad(out_h5ad)
    print(f"[GPU_ANALYSIS] Saved embeddings: {out_h5ad}", flush=True)

    # 3. Training history
    history_path = out_dir / "training_history.csv"
    pd.DataFrame(history).to_csv(history_path, index=False)
    print(f"[GPU_ANALYSIS] Saved training history: {history_path}", flush=True)

    print("[GPU_ANALYSIS] Done.", flush=True)
    NF_PYEOF
    """
}
