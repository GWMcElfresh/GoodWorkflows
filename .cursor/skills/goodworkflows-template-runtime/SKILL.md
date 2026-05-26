---
name: goodworkflows-template-runtime
description: Edit and debug GoodWorkflows R, Python, and shell templates that run inside Nextflow containers. Use for modules/local/**/templates, Apptainer runtime issues, Numba cache failures, AnnData write_h5ad errors, sparse matrix memory bugs, or Groovy template escaping.
---

# GoodWorkflows Template Runtime

Use this when changing files under `modules/local/**/templates/` or scripts rendered through Nextflow `template`.

## Runtime Context

Templates execute inside containers, often through Apptainer on read-only squashfs images. Bugs may only appear after Nextflow renders the template into `.command.sh`.

## Python Templates

- Set `NUMBA_CACHE_DIR` before imports that may touch `numba`, `scanpy`, `umap`, `pynndescent`, or scipy sparse graph code:

```python
import os
os.environ["NUMBA_CACHE_DIR"] = "/tmp"
```

- Before `write_h5ad()`, coerce all `adata.obs` columns to strings unconditionally. Mixed object columns with `NaN` can still fail HDF5 string writes.
- Keep merge and harmonize matrices sparse unless the downstream model stage explicitly owns densification.
- Avoid raw `\n` and `\t` string literals in rendered templates when they have caused Groovy escape stripping; prefer `chr(10)` and `chr(9)`.

## R Templates

- Prefer `df[["col"]]` and `obj[["slot"]]` over `$` access.
- If `$` is necessary, escape it as `\$` in template files.
- Avoid `file.copy(from, to)` when the staged file and output name are the same; read the staged file directly.
- Avoid data.table `..keep_cols` patterns on plain data frames; use `df[, keep_cols, drop = FALSE]`.

## Debugging

1. Inspect `nextflow.log` from the bottom upward and find the first real exception.
2. Inspect the generated `.command.sh` in the work directory when errors mention syntax or missing variables.
3. For container-specific failures, reproduce with `apptainer exec <image.sif> python3 <script>` or the matching R command.
4. If a fix appears ignored, clear the affected Nextflow work directory before retesting.
