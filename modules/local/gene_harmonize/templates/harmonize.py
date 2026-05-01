#!/usr/bin/env python3
"""
Nextflow template: harmonize.py
Gene ortholog mapping and cross-species AnnData harmonization for GENE_HARMONIZE.

Nextflow substitutions (resolved before Python runs):
  ${params.species_order}  – comma-separated canonical species ordering
"""

import pathlib
import re
import time
from collections import defaultdict

import anndata as ad
import mygene
import numpy as np
import pandas as pd
import scanpy as sc
from scipy import io, sparse

# ---------------------------------------------------------------------------
# Nextflow-injected parameters
# ---------------------------------------------------------------------------
SPECIES_ORDER_RAW = "${params.species_order}"

# ---------------------------------------------------------------------------
# Species taxonomy registry
# ---------------------------------------------------------------------------
SPECIES_CONFIG = {
    "human": {
        "taxid": 9606,
        "aliases": {"human", "homo_sapiens", "homo sapiens", "hs"},
    },
    "macaque": {
        "taxid": 9544,
        "aliases": {
            "macaque",
            "rhesus",
            "rhesus_macaque",
            "rhesus macaque",
            "macaca_mulatta",
            "macaca mulatta",
            "monkey",
        },
    },
    "mouse": {
        "taxid": 10090,
        "aliases": {"mouse", "mus_musculus", "mus musculus", "mm"},
    },
}
HUMAN_TAXID = 9606

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def normalize_token(value):
    return re.sub(r"[^a-z0-9]+", "_", str(value).strip().lower()).strip("_")


def canonicalize_species(value):
    token = normalize_token(value)
    for canonical, config in SPECIES_CONFIG.items():
        alias_tokens = {normalize_token(alias) for alias in config["aliases"]}
        if token == canonical or token in alias_tokens:
            return canonical
    raise ValueError(f"Unsupported species label: {value!r}")


def read_count_dir(count_dir):
    for required in ("features.tsv", "barcodes.tsv", "obs_meta.csv", "matrix.mtx"):
        if not (count_dir / required).exists():
            raise RuntimeError(f"Missing required file {required!r} in {count_dir}")

    genes = pd.read_csv(count_dir / "features.tsv", sep="\t", header=None)[0].astype(str).tolist()
    barcodes = pd.read_csv(count_dir / "barcodes.tsv", sep="\t", header=None)[0].astype(str).tolist()
    obs = pd.read_csv(count_dir / "obs_meta.csv", index_col=0)
    obs.index = obs.index.astype(str)
    obs = obs.reindex(barcodes)

    if obs.isnull().all(axis=1).any():
        missing = obs.index[obs.isnull().all(axis=1)].tolist()[:5]
        raise RuntimeError(
            f"obs_meta rows did not align to barcodes for {count_dir}: {missing}"
        )

    sample_id = (
        str(obs["sample_id"].iloc[0])
        if "sample_id" in obs.columns
        else count_dir.name.replace("_counts", "")
    )
    species = canonicalize_species(obs["species"].iloc[0])
    matrix = io.mmread(count_dir / "matrix.mtx").tocsr().transpose().tocsr()

    if matrix.shape != (len(barcodes), len(genes)):
        raise RuntimeError(
            f"Matrix shape mismatch for {count_dir}: got {matrix.shape}, "
            f"expected {(len(barcodes), len(genes))}"
        )

    obs = obs.copy()
    obs["sample_id"] = sample_id
    obs["species"] = species
    obs["original_barcode"] = barcodes
    obs.index = pd.Index(
        [f"{sample_id}:{barcode}" for barcode in barcodes], name="cell_id"
    )

    var = pd.DataFrame(
        index=pd.Index(
            [f"feature_{idx}" for idx in range(len(genes))], name="feature_id"
        )
    )
    var["feature_name"] = genes
    return ad.AnnData(X=matrix, obs=obs, var=var)


def fetch_species_mapping(mg_client, species, genes, max_retries=3, retry_delay=10):
    """Query mygene.info for HomoloGene ortholog records, with retry on transient errors."""
    unique_genes = list(dict.fromkeys(str(g) for g in genes if pd.notna(g)))
    last_exc = None
    for attempt in range(1, max_retries + 1):
        try:
            results = mg_client.querymany(
                unique_genes,
                scopes="symbol",
                fields="symbol,homologene",
                species=SPECIES_CONFIG[species]["taxid"],
                as_dataframe=False,
                returnall=False,
                verbose=False,
            )
            break
        except Exception as exc:  # noqa: BLE001
            last_exc = exc
            if attempt == max_retries:
                raise RuntimeError(
                    f"mygene API failed for species '{species}' after {max_retries} attempts: {exc}"
                ) from exc
            wait = retry_delay * attempt
            print(
                f"WARNING: mygene attempt {attempt}/{max_retries} failed ({exc}). "
                f"Retrying in {wait}s …",
                flush=True,
            )
            time.sleep(wait)

    best_hits = {}
    for result in results:
        query = str(result.get("query", "")).strip()
        if not query or result.get("notfound"):
            continue

        homologene = result.get("homologene")
        if not isinstance(homologene, dict) or "id" not in homologene or "genes" not in homologene:
            continue

        try:
            homologene_id = int(homologene["id"])
        except (TypeError, ValueError):
            continue

        score = float(result.get("_score", float("-inf")))
        previous = best_hits.get(query)
        if previous is not None and score <= previous["mygene_score"]:
            continue

        human_symbol = None
        for entry in homologene.get("genes", []):
            if isinstance(entry, (list, tuple)) and len(entry) >= 2:
                try:
                    entry_taxid = int(entry[0])
                except (TypeError, ValueError):
                    continue
                if entry_taxid == HUMAN_TAXID:
                    human_symbol = str(entry[1]).upper()
                    break

        best_hits[query] = {
            "species": species,
            "original_gene": query,
            "matched_symbol": str(result.get("symbol", query)),
            "homologene_id": homologene_id,
            "canonical_gene": human_symbol or f"HOMOLOGENE_{homologene_id}",
            "mygene_score": score,
        }

    mapping = pd.DataFrame(best_hits.values())
    if mapping.empty:
        raise RuntimeError(f"No ortholog mappings were found for species '{species}'.")

    return mapping.sort_values(
        ["canonical_gene", "mygene_score", "original_gene"],
        ascending=[True, False, True],
    ).reset_index(drop=True)


def collapse_to_canonical(adata, mapping_df, shared_gene_set):
    feature_map = mapping_df.drop_duplicates("original_gene").set_index("original_gene")["canonical_gene"]
    canonical = adata.var["feature_name"].map(feature_map)
    keep_mask = canonical.notna() & canonical.isin(shared_gene_set)
    if not keep_mask.any():
        raise RuntimeError(
            f"No shared genes remained for sample {adata.obs['sample_id'].iloc[0]}."
        )

    matrix = adata.X[:, keep_mask.to_numpy()].tocsr()
    canonical_names = canonical[keep_mask].astype(str).reset_index(drop=True)
    codes, unique_names = pd.factorize(canonical_names, sort=False)
    coo = matrix.tocoo()

    collapsed = sparse.coo_matrix(
        (coo.data, (coo.row, codes[coo.col])),
        shape=(matrix.shape[0], len(unique_names)),
        dtype=np.float32,
    ).tocsr()

    var = pd.DataFrame(index=pd.Index(unique_names, name="feature_name"))
    var["feature_name"] = var.index.astype(str)
    return ad.AnnData(X=collapsed, obs=adata.obs.copy(), var=var)


def align_features(adata, target_genes):
    target_lookup = {gene: idx for idx, gene in enumerate(target_genes)}

    # Guard: every gene in adata must be in target_lookup after collapse_to_canonical
    missing = [g for g in adata.var_names if g not in target_lookup]
    if missing:
        raise RuntimeError(
            f"align_features: {len(missing)} gene(s) not in shared set after collapse "
            f"(first 5: {missing[:5]}). This is a bug — please report it."
        )

    column_positions = np.array(
        [target_lookup[gene] for gene in adata.var_names], dtype=np.int64
    )
    coo = adata.X.tocoo()

    aligned = sparse.coo_matrix(
        (coo.data, (coo.row, column_positions[coo.col])),
        shape=(adata.n_obs, len(target_genes)),
        dtype=np.float32,
    ).tocsr()

    var = pd.DataFrame(index=pd.Index(target_genes, name="feature_name"))
    var["feature_name"] = var.index.astype(str)
    return ad.AnnData(X=aligned, obs=adata.obs.copy(), var=var)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

output_dir = pathlib.Path("harmonized_outputs")
output_dir.mkdir(exist_ok=True)

count_dirs = sorted(pathlib.Path(".").glob("*_counts"))
if not count_dirs:
    raise RuntimeError(
        "No per-sample counts directories were staged for GENE_HARMONIZE. "
        "Expected directories matching '*_counts' in the work directory."
    )

requested_order = []
for raw_species in [s for s in SPECIES_ORDER_RAW.split(",") if s.strip()]:
    canonical = canonicalize_species(raw_species)
    if canonical not in requested_order:
        requested_order.append(canonical)

mg = mygene.MyGeneInfo()

adatas_by_species = defaultdict(list)
for count_dir in count_dirs:
    adata = read_count_dir(count_dir)
    adatas_by_species[adata.obs["species"].iloc[0]].append(adata)

present_species = list(adatas_by_species.keys())
if len(present_species) < 2:
    raise RuntimeError(
        f"scMODAL integration requires at least two species datasets; "
        f"found: {present_species}"
    )

ordered_species = [s for s in requested_order if s in present_species]
ordered_species.extend(sorted(s for s in present_species if s not in ordered_species))

mapping_frames = []
species_mappings = {}
canonical_sets = {}
for species in ordered_species:
    all_genes = []
    for adata in adatas_by_species[species]:
        all_genes.extend(adata.var["feature_name"].astype(str).tolist())
    mapping_df = fetch_species_mapping(mg, species, all_genes)
    mapping_frames.append(mapping_df)
    species_mappings[species] = mapping_df
    canonical_sets[species] = set(mapping_df["canonical_gene"].tolist())

shared_gene_set = set.intersection(*(canonical_sets[s] for s in ordered_species))
if not shared_gene_set:
    raise RuntimeError(
        "No shared ortholog-mapped genes were found across the requested species. "
        f"Species: {ordered_species}"
    )

reference_species = "human" if "human" in ordered_species else ordered_species[0]
shared_gene_order = []
for gene in species_mappings[reference_species]["canonical_gene"]:
    if gene in shared_gene_set and gene not in shared_gene_order:
        shared_gene_order.append(gene)
for gene in sorted(shared_gene_set):
    if gene not in shared_gene_order:
        shared_gene_order.append(gene)

manifest_rows = []
for order_index, species in enumerate(ordered_species):
    aligned_adatas = []
    for adata in adatas_by_species[species]:
        collapsed = collapse_to_canonical(adata, species_mappings[species], shared_gene_set)
        aligned_adatas.append(align_features(collapsed, shared_gene_order))

    species_adata = ad.concat(aligned_adatas, join="inner", merge="same", index_unique=None)
    species_adata.obs["species"] = species
    species_adata.obs["species_order_index"] = order_index

    sc.pp.normalize_total(species_adata, target_sum=1e4)
    sc.pp.log1p(species_adata)

    dense_x = (
        species_adata.X.toarray()
        if sparse.issparse(species_adata.X)
        else np.asarray(species_adata.X)
    )
    dense_x = dense_x.astype(np.float32, copy=False)
    gene_mean = dense_x.mean(axis=0)
    gene_std = dense_x.std(axis=0)
    gene_std[gene_std == 0] = 1.0
    species_adata.X = ((dense_x - gene_mean) / gene_std).astype(np.float32, copy=False)
    species_adata.var["mean"] = gene_mean
    species_adata.var["std"] = gene_std
    species_adata.var["feature_name"] = species_adata.var_names.astype(str)

    output_name = f"{order_index:02d}_{species}_harmonized.h5ad"
    species_adata.write_h5ad(output_dir / output_name)

    manifest_rows.append(
        {
            "order_index": order_index,
            "species": species,
            "taxonomy_id": SPECIES_CONFIG[species]["taxid"],
            "n_cells": int(species_adata.n_obs),
            "n_genes": int(species_adata.n_vars),
            "h5ad_file": output_name,
        }
    )

pd.concat(mapping_frames, ignore_index=True).to_csv(
    output_dir / "ortholog_mapping.csv", index=False
)
pd.DataFrame(
    {"feature_index": range(len(shared_gene_order)), "canonical_gene": shared_gene_order}
).to_csv(output_dir / "shared_genes.csv", index=False)
pd.DataFrame(manifest_rows).to_csv(output_dir / "integration_manifest.csv", index=False)
(output_dir / "n_shared.txt").write_text(f"{len(shared_gene_order)}\\n")

# Validate outputs exist
required_outputs = [
    output_dir / "ortholog_mapping.csv",
    output_dir / "shared_genes.csv",
    output_dir / "integration_manifest.csv",
    output_dir / "n_shared.txt",
]
for path in required_outputs:
    if not path.exists():
        raise RuntimeError(f"GENE_HARMONIZE: expected output not created: {path}")
for row in manifest_rows:
    h5ad = output_dir / row["h5ad_file"]
    if not h5ad.exists():
        raise RuntimeError(f"GENE_HARMONIZE: expected species h5ad not created: {h5ad}")

print(
    f"GENE_HARMONIZE complete: {len(ordered_species)} species, "
    f"{len(shared_gene_order)} shared genes, "
    f"{sum(r['n_cells'] for r in manifest_rows)} total cells.",
    flush=True,
)
