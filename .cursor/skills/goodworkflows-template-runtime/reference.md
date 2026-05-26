# GoodWorkflows Template Runtime Reference

Detailed runtime notes migrated from the retired root `skills/` directory.

## Numba Cache in Apptainer

Apptainer/Singularity images can be read-only, so imports that trigger Numba caching may fail with "no locator available". Set the cache directory before imports that transitively load Numba:

```python
import os
os.environ["NUMBA_CACHE_DIR"] = "/tmp"
```

Watch templates/scripts that import or trigger `scanpy`, `umap`, `pynndescent`, scipy graph code, or ESM/TCR embedding utilities.

## Groovy Escape Stripping

Nextflow `template` files are rendered by Groovy before Python/R/Shell runs. Raw `\n`, `\t`, and `\r` in template strings can become literal newline/tab characters in generated scripts.

Safer patterns:

```python
path.write_text(chr(10).join(values) + chr(10))
pd.read_csv("file.tsv", sep=chr(9))
```

Inspect generated `.command.sh` if Python reports a syntax error at a split string.

## AnnData String Coercion

Before `write_h5ad()`, coerce all `obs` columns to string unconditionally:

```python
for col in adata.obs.columns:
    adata.obs[col] = adata.obs[col].astype(str)
```

Do not guard only on dtype; mixed object columns with `NaN` can still fail in HDF5 writes.

## Sparse vs Dense Ownership

- `GENE_HARMONIZE`: keep CSR float32 raw counts; do not normalize or densify.
- Merge processes: keep sparse/raw when possible.
- Model stages such as scModal, NMF-VAE, and MIL own normalization and may densify in the right compute profile.

Dense conversion of large sparse matrices can create huge float64 temporaries and trigger OOM.

## R Template Patterns

- Prefer `df[["col"]]`, `obj[["slot"]]`, and `df[, cols, drop = FALSE]`.
- Escape unavoidable `$` as `\$`.
- Avoid `file.copy(from, to)` when the staged input and output name are identical; read the staged file directly.
- Avoid unavailable helper operators such as `%||%` unless the container provides them.

## Debugging

1. Find the first error in `nextflow.log`.
2. Inspect generated `.command.sh`.
3. Reproduce inside the container with `apptainer exec <image.sif> ...` when possible.
4. Clear stale work dirs before assuming a template fix did not apply.
