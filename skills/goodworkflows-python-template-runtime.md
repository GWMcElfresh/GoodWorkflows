---
name: goodworkflows-python-template-runtime
description: "Python template runtime errors and their fixes in GoodWorkflows Nextflow containers. Covers Apptainer/Singularity environment pitfalls, Numba/JIT failures, scipy/scanpy AnnData issues, and memory/escape bugs specific to Nextflow template rendering."
version: 1.0.0
metadata:
  hermes:
    tags: [goodworkflows, nextflow, python, template, container, runtime, scanpy, numba]
---

# GoodWorkflows Python Template Runtime

Python templates (`.py`, `.r`, `.sh` via `template 'file'`) in GoodWorkflows run inside Apptainer/Singularity containers. Some bugs are specific to that environment.

## 1. Numba JIT Cache Failure — "cannot cache function"

Apptainer containers mount a read-only squashfs filesystem — Numba's JIT cache cannot write alongside source files. The `@vectorize` decorator's `enable_caching()` path (in `pynndescent` → `umap` deep imports) raises `RuntimeError: no locator available`.

**Fix:** Redirect cache to `/tmp` before any Numba-using imports:
```python
import os
os.environ['NUMBA_CACHE_DIR'] = '/tmp'
```

For Nextflow templates, the comment-style pattern also works (Nextflow treats it as text but doesn't interpret it — it must be `os.environ`):
```python
#!/usr/bin/env python3
import os
os.environ['NUMBA_CACHE_DIR'] = '/tmp'
# rest of imports follow
```

**Files affected:**
- `modules/local/scModal/gpu/templates/integrate.py` — `sc.pp.neighbors`, `sc.tl.umap`, `sc.tl.leiden`
- `modules/local/tcr_epitope/embed/templates/embed_esm2.py`
- `modules/local/tcr_epitope/predict_binding/templates/predict_binding.py`
- `modules/local/tcr_epitope/tcr_umap/templates/tcr_umap.py`
- `modules/local/tcr_epitope/train_binding/templates/train_binding.py`
- `scripts/train_tcr_epitope_binding.py`

Any Python template calling `sc.pp.*`, `scanpy.*`, or scipy sparse operations inside an Apptainer container should set this.

## 2. Groovy `\n`/`\t` Escape Stripping Before Python Runs

When Nextflow renders `template 'file.py'`, Groovy processes `\n` → literal newline and `\t` → literal tab BEFORE the text reaches Python. This produces `SyntaxError: unterminated string literal`.

**Recognition:** Error points at `print("` or similar string-opening delimiter with nothing after it. The generated `.command.sh` shows the string broken mid-line.

**Fix:** Double the backslash or use `chr()`:
```python
# Correct in template
print("\\nSCMODAL: starting...", flush=True)
pathlib.Path("genes.txt").write_text(chr(10).join(genes) + chr(10))
pd.read_csv("file.tsv", sep=chr(9))
```

## 3. h5py TypeError: Non-String Objects in AnnData obs — `write_h5ad` Fails

Two root causes: integer columns from R (`cDNA_ID` as `int64`) or mixed-type object columns (strings with float NaN). h5py rejects non-string elements in HDF5 string datasets.

**Fix:** Convert ALL obs columns to `str` unconditionally before every `write_h5ad()`:
```python
for col in adata.obs.columns:
    adata.obs[col] = adata.obs[col].astype(str)
```

Do NOT use `if dtype != object:` guard — mixed-type object columns with float NaN slip through.

**Files requiring fix** (search for `write_h5ad`):
- `modules/local/gene_harmonize/templates/harmonize.py`
- `modules/local/nmf_vae/merge_counts/templates/merge_counts.py`
- `modules/local/scModal/gpu/templates/integrate.py`
- `modules/local/mil_ton/gex_merge/templates/merge_gex.r` (coerce in R)

## 4. Dense Matrix Conversion OOM — `toarray()` on Large Sparse Data

`scipy.sparse.csr_matrix.toarray()` on large data (200K cells × 20K genes) produces 32 GB dense float64 copy. With z-score temporaries, peak reaches 70-90 GB.

**GENE_HARMONIZE:** Keep CSR float32. Never densify/normalize.
**SCMODAL_INTEGRATE:** OK to densify — GPU nodes, no z-score temps, per-species loading.
**MERGE processes:** Keep CSR sparse. Model/ML processes own normalization.

## 5. Debugging Template Runtime Errors

1. Isolate the template: `apptainer exec <image.sif> python3 /path/to/template.py`
2. Check Numba cache: `NUMBA_DEBUG_CACHE=1 python3 script.py`
3. Check if packages are zip archives: `python3 -c "import scanpy; print(scanpy.__file__)"`
