/*
 * Process: SCMODAL_INTEGRATE
 *
 * Consumes harmonized species-level AnnData files, trains scMODAL, writes the
 * latent embedding, and clusters cells in scMODAL space with Leiden.
 */

process SCMODAL_INTEGRATE {
    label 'process_gpu'

    container "${params.scmodal_container}"

    publishDir "${params.outdir}/scmodal", mode: 'copy'

    input:
    path harmonized_dir

    output:
    path 'model_outputs/', emit: model

    stub:
    """
    mkdir -p model_outputs
    touch model_outputs/ckpt.pth
    touch model_outputs/latent_clustered.h5ad
    touch model_outputs/training_history.csv
    touch model_outputs/gpu_info.txt
    touch model_outputs/run_summary.json
    """

    script:
    """
    python3 - << 'NF_PYEOF'
    import json
    import os
    import subprocess
    import pathlib
    import shutil

    import anndata as ad
    import numpy  as np
    import pandas as pd
    import scanpy as sc
    import torch
    from scipy import sparse

    from scmodal.model import Model

    out_dir = pathlib.Path("model_outputs")
    out_dir.mkdir(exist_ok=True)
    harmonized_dir = pathlib.Path("${harmonized_dir}")

    try:
        result = subprocess.run(
            ["nvidia-smi"], capture_output=True, text=True, check=True
        )
        (out_dir / "gpu_info.txt").write_text(result.stdout)
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        msg = f"WARNING: nvidia-smi failed: {exc}\\n"
        (out_dir / "gpu_info.txt").write_text(msg)

    manifest = pd.read_csv(harmonized_dir / "integration_manifest.csv")
    manifest = manifest.sort_values("order_index").reset_index(drop=True)
    if manifest.empty:
        raise RuntimeError("integration_manifest.csv is empty.")

    adatas = []
    for row in manifest.itertuples(index=False):
        adata = sc.read_h5ad(harmonized_dir / row.h5ad_file)
        if sparse.issparse(adata.X):
            adata.X = adata.X.toarray().astype(np.float32)
        else:
            adata.X = np.asarray(adata.X, dtype=np.float32)
        adatas.append(adata)

    model_dir = out_dir / "scmodal_model"
    model = Model(
        batch_size=int("${params.scmodal_batch_size}"),
        training_steps=int("${params.scmodal_training_steps}"),
        n_latent=int("${params.scmodal_latent}"),
        n_KNN=int("${params.scmodal_neighbors}"),
        model_path=str(model_dir),
        result_path=str(out_dir),
    )

    if len(adatas) == 2:
        shared_gene_num = int((harmonized_dir / "n_shared.txt").read_text().strip())
        model.preprocess(adatas[0], adatas[1], shared_gene_num)
        model.train()
        model.eval()
    else:
        input_feats = [adata.X for adata in adatas]
        paired_inputs = [[input_feats[idx], input_feats[idx + 1]] for idx in range(len(input_feats) - 1)]
        model.integrate_datasets_feats(input_feats=input_feats, paired_input_MNN=paired_inputs)

    combined = ad.concat(
        adatas,
        join="inner",
        merge="same",
        label="integration_species",
        keys=manifest["species"].tolist(),
        index_unique=None,
    )
    combined.obsm["X_scmodal"] = model.latent.astype(np.float32, copy=False)

    n_neighbors = min(int("${params.scmodal_neighbors}"), max(2, combined.n_obs - 1))
    sc.pp.neighbors(combined, use_rep="X_scmodal", n_neighbors=n_neighbors)
    sc.tl.umap(combined)
    sc.tl.leiden(combined, resolution=float("${params.leiden_resolution}"))

    combined.uns["scmodal"] = {
        "species_order": manifest["species"].tolist(),
        "n_latent": int("${params.scmodal_latent}"),
        "training_steps": int("${params.scmodal_training_steps}"),
        "device": str(model.device),
    }

    combined.write_h5ad(out_dir / "latent_clustered.h5ad")
    shutil.copy2(model_dir / "ckpt.pth", out_dir / "ckpt.pth")
    shutil.copy2(harmonized_dir / "integration_manifest.csv", out_dir / "integration_manifest.csv")
    shutil.copy2(harmonized_dir / "shared_genes.csv", out_dir / "shared_genes.csv")

    training_summary = pd.DataFrame(
        [
            {
                "n_species": len(adatas),
                "n_cells": int(combined.n_obs),
                "n_genes": int(combined.n_vars),
                "n_latent": int("${params.scmodal_latent}"),
                "training_steps": int("${params.scmodal_training_steps}"),
                "batch_size": int("${params.scmodal_batch_size}"),
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
                "n_latent": int("${params.scmodal_latent}"),
                "device": str(model.device),
            },
            indent=2,
        )
    )
    NF_PYEOF
    """
}
