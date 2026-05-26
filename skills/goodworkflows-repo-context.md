---
name: goodworkflows-repo-context
description: "GoodWorkflows repo context: DSL2 Nextflow single-cell RNA-seq pipeline repo for SLURM+Apptainer HPC. Contains architecture, conventions, configs, modules, workflows, and tech stack details."
version: 1.0.1
metadata:
  hermes:
    tags: [goodworkflows, nextflow, dsl2, single-cell, scRNA-seq, bioinformatics, hpc, slurm, apptainer]
---

# GoodWorkflows Repo Context

**Repo:** https://github.com/GWMcElfresh/GoodWorkflows
**Docs:** https://gwmcelfresh.github.io/GoodWorkflows/
**License:** MIT

## What It Does

A DSL2 Nextflow pipeline for composing reusable single-cell RNA-seq workflows from small, independently testable modules. Targets SLURM + Apptainer HPC systems but also supports local CPU/GPU execution.

Core pipeline: download single-cell Seurat objects from LabKey/URL/local file → export 10x-like count matrices → harmonize genes across species via ortholog mapping → train scMODAL for cross-species latent embedding with Leiden clustering.

## All Seven Workflows

| Name | CLI | Stages | Compute | Samplesheet |
|---|---|---|---|---|
| Integration Pipeline | `--workflow integration` | INGEST → EXPORT_COUNTS → GENE_HARMONIZE → SCMODAL_INTEGRATE | HPC + GPU (A100s, 1TB RAM) | `samplesheet.csv` |
| Ingest + Export | `--workflow ingest_export` | INGEST → EXPORT_COUNTS | CPU (local or HPC) | `samplesheet.csv` |
| Ingest + Tabulate | `--workflow ingest_tabulate` | INGEST_METADATA → TABULATE | CPU (local or HPC) | `tabulate_samplesheet.csv` |
| NMF-VAE Factorize | `--workflow nmf_vae` | INGEST → EXPORT_COUNTS → NMF_VAE_MERGE_COUNTS → NMF_VAE_FACTORIZE | GPU (A100s) or CPU fallback | `nmf_vae_samplesheet.csv` |
| GEX MIL Pipeline | `--workflow gex_mil` | INGEST → EXPORT_COUNTS → GEX_MERGE_COUNTS → TRAIN_GEX_MIL | GPU (A100s) | `samplesheet.csv` (requires `SubjectId` column) |
| TCR MIL Pipeline | `--workflow tcr_mil` | INGEST → QUANTIFY_TCR → MERGE_TCR_METADATA → TRAIN_TCR_MIL | GPU (A100s) | `samplesheet.csv` |
| TCR Epitope | `--workflow tcr_epitope` | INGEST → QUANTIFY_TCR → MERGE_TCR_METADATA → EMBED_CLONES → PREDICT_BINDING → TCR_UMAP → JOIN_SEURAT | GPU (A100s) | `tcr_epitope_samplesheet.csv` (requires `--binding_model_path`) |

## Execution Profiles

| Profile | Runtime | Use Case | Resources |
|---|---|---|---|
| `local` | Podman | macOS/Linux dev (no GPU) | 3 CPU, 6GB RAM, maxForks=1 |
| `local_gpu` | Podman + `--gpus all` | Local workstation GPU | 32GB RAM / 8GB vRAM, maxForks=1. Overrides `scmodal_training_steps = 100` (vs 10,000 in base.config) for fast local testing. |
| `slurm` | Podman (rootless) | HPC reference (stubbed, not actively used) | 64GB RAM, SLURM executor |
| `slurm_singularity` | Apptainer (SIF cache) | Primary HPC profile | A100s, 1TB RAM. GPU processes use `queue = 'gpu'` partition via `process_gpu`/`process_nmf_vae` labels. |
| `test_tcr_mil` | None (stub-run) | CI smoke tests for mil-ton workflows | 2 CPU, 8GB RAM, containers disabled, uses base.config + local-gpu.config |
| `test` | None (stub-run) | Legacy CI profile (kept for backward compat) | 1 CPU, 2GB RAM |

### New Module: INGEST_METADATA_FILE

`modules/local/rdiscvr/ingest_metadata_file/` — reads standalone metadata CSVs for the `ingest_tabulate` workflow. Accepts `tuple val(meta), path(metadata_file)` input, validates `cDNA_ID` column exists, enriches with `sample_id`/`species`/`source_path`, emits `{id}_metadata.csv`. Uses the `rdiscvr:latest` container.

## Four-Mode Ingest

Every sample row uses exactly one of:
- `output_file_id` — LabKey download (requires `.netrc` mount)
- `url` — HTTP download
- `path` — Local Seurat `.rds` file (INGEST_FILE)
- `metadata_path` — Standalone metadata CSV (INGEST_METADATA_FILE, ingest_tabulate only)

**Input format:** `INGEST_FILE` and `INGEST_METADATA_FILE` expect `tuple val(meta), path(file)`. Workflow branches must wrap bare `meta` with `.map { meta -> [meta, file(meta.field)] }`. `INGEST_URL` and `INGEST_METADATA` only need `val(meta)` — no wrapping.

### File-Mode Tuple Wrapping (Critical)

```groovy
// ❌ FAIL — bare meta passed to process expecting (meta, path) tuple
INGEST_FILE(ch_labkey.file).rds

// ✅ PASS — proper tuple wrapping
INGEST_FILE(ch_labkey.file.map { meta -> [meta, file(meta.path)] }).rds
```

## Preprocessing Ownership Architecture

A key design principle that emerged from OOM debugging (2026-05-15). Each module owns exactly one responsibility — don't duplicate preprocessing.

| Stage | Module | What It Does | Keeps X Sparse? | Normalizes? |
|---|---|---|---|---|
| Export | EXPORT_COUNTS | Seurat → 10x-format (matrix.mtx + obs_meta.csv) | n/a (writes CSV/MTX) | No |
| Gene mapping | GENE_HARMONIZE | Ortholog ID lookup, collapse to canonical genes, align to shared set | **Yes** (raw CSR float32) | **No** — scMODAL normalizes internally |
| Merge (NMF-VAE) | NMF_VAE_MERGE_COUNTS | Stack samples vertically, filter to shared genes | **Yes** (raw CSR) | No |
| Merge (GEX) | GEX_MERGE_COUNTS | Stack samples, merge metadata | **Yes** (raw CSR → h5ad) | No |
| Integration | SCMODAL_INTEGRATE | Cross-species latent embedding via scMODAL | No — densifies on read (line 142 integrate.py) | Yes — `model.preprocess()` or `integrate_datasets_feats()` do their own |
| Factorize | NMF_VAE_FACTORIZE | NMF-VAE training | No — model expects dense | Yes — model internal |
| MIL training | TRAIN_GEX_MIL / TRAIN_TCR_MIL | MIL model training | n/a | Yes — dataloader normalizes |

**Rule of thumb for template authors:**
- If your process name is HARMONIZE, MERGE, or EXPORT → **do not normalize, do not densify.** Write sparse h5ad with raw counts.
- If your process trains a model (INTEGRATE, FACTORIZE, MIL) → **you own normalization.** Densification is fine here — you're running on GPU nodes with high RAM.
- If you're unsure, check the downstream consumer. If the downstream process calls `.toarray()` or `.astype(np.float32)` on read, it owns normalization. Don't duplicate.

**Concrete example of the rule (GENE_HARMONIZE, fixed 2026-05-15):**
The previous implementation called `sc.pp.normalize_total`, `sc.pp.log1p`, then `toarray()` + z-score standardization. SCMODAL_INTEGRATE's `model.preprocess()` re-normalizes anyway. Removing the normalization/densification block:
- Eliminated OOM (exit 137) on large datasets by keeping X sparse CSR
- Removed unused `var["mean"]` / `var["std"]` columns (no downstream consumer)
- Removed `import scanpy` — no longer needed

## Container Images
**Container images:**
| Image | Modules |
|---|---|
| `ghcr.io/gwmcelfresh/mil-ton` | GEX_MERGE_COUNTS, TRAIN_GEX_MIL, MERGE_TCR_METADATA, TRAIN_TCR_MIL |

See `references/milton-wrappers.md` for full MIL pipeline details: module file paths, template technical notes, key mil-ton classes, configuration parameters, and pipeline-specific gotchas.

**R packages in container images:** Several GoodWorkflows processes use R templates.
See `references/r-packages-in-container-builds.md` for Dockerfile debugging guidance,
including the `install.packages(c(...))` silent-failure trap that can leave R packages
absent despite a successful CI build.
| `ghcr.io/bimberlabinternal/cellmembrane:latest` | EXPORT_COUNTS |
| `ghcr.io/gwmcelfresh/scmodal:latest` | GENE_HARMONIZE, SCMODAL_INTEGRATE — includes scMODAL package with checkpoint resume support. Model.train() and integrate_datasets_feats() auto-detect ckpt.pth and resume from saved step. Periodic checkpoint every 2000 steps. SIGTERM handler saves checkpoint on graceful SLURM kill. See `references/scmodal-checkpointing.md` for details. |
| `ghcr.io/gwmcelfresh/nmf-vae:latest` | NMF_VAE_MERGE_COUNTS, NMF_VAE_FACTORIZE |

## Key Naming Conventions

- **Modules:** `snake_case` dirs with `main.nf` entry
- **Workflows:** `snake_case.nf` files
- **Process names:** `UPPER_SNAKE_CASE` (INGEST, EXPORT_COUNTS, etc.)
- **Workflow names:** `UPPER_SNAKE_CASE` (INTEGRATION_PIPELINE, etc.)
- **Config files:** `lowercase.config` or `lowercase.profile.config`
- **Process labels:** `process_ingest_labkey`, `process_export`, `process_gpu`, etc.

## DSL2 Critical Constraints

1. **No top-level variable/function definitions** — must be inside `workflow {}`, `process {}`, or function blocks
2. **No input interpolation in directives** — `tag` and `publishDir` must use static strings (no `${meta.id}`)
3. **No `switch` blocks in workflow** — use `if/else if/else` chains
4. **`stub:` must appear AFTER `script:`** — ordering matters
5. **Escape `$` in R/Python heredocs** — see Groovy Template Escaping section below
6. **Flattened output layout** — `publishDir` can't use `${meta.id}`, so outputs go flat into top-level dirs
7. **No `onError:` execution scope** — valid workflow-level scopes are ONLY `onStart:`, `onComplete:`, `onStop:`. Error handling uses `workflow.success` guard inside `onComplete:`, not a separate `onError:` block. Per-process retry is via `errorStrategy` in config.

```groovy
// ✅ Correct — error logging inside onComplete
onComplete:
if (workflow.success) {
    log.info "Done: ${workflow.duration}"
} else {
    log.error "Failed: ${workflow.errorMessage}"
}

// ❌ INVALID — onError: is not a recognized DSL2 scope
onError:
log.error "Failed: ${workflow.errorMessage}"
```

## Every Process MUST Have a `stub:` Block

Enables `-stub-run` for CI smoke tests. Creates expected output files even if empty/touched.

## Error Handling

- SLURM: retry on exit 1 (3x with jitter), retry on 125/137 (5x)
- Local: retry on OOM (exit 137) with increasing memory
- GPU guard: INTEGRATION_PIPELINE errors on local executor unless `--scmodal_use_cpu` or `-profile local_gpu`

### Memory Escalation on OOM (slurm config)

**All processes** in `configs/slurm.config` use attempt-based memory escalation. The escalation map is inlined inside each `memory` closure (not a top-level variable — Nextflow rejects mixing `def` declarations with config blocks when multiple configs merge):

```groovy
memory = { def levels = [1:64, 2:128, 3:256, 4:512, 5:999, 6:999]; "${levels[Math.min(task.attempt, 6)]}.GB" }
```

Escalation ladder: attempt 1→64, 2→128, 3→256, 4→512, 5+→999 GB.
Applied to: **every process** (default + all labels: process_ingest_*, process_export, process_harmonize, process_tabulate, process_gpu, process_nmf_vae).

The default `errorStrategy` retries on exit 137 (OOM) with `<=` 5 attempts, so attempt 5 at 999 GB actually runs before giving up. `maxRetries = 5`.

**`process_gpu` and `process_nmf_vae`** have a *separate* errorStrategy that retries on exit 42 (CUDA OOM sentinel), exit 137 (OS SIGKILL), **and exit 143 (SLURM time-limit / preemption SIGTERM)**. `integrate.py` has a SIGTERM handler that saves a checkpoint before exiting 143, so the retry resumes from the last periodic save. Their memory directive uses the same escalation map. Both submit to `queue = 'gpu'` (not `'batch'`) with `--gres=gpu:1` for GPU node allocation.

⚠️ **Do not add top-level `def` variables to `slurm.config`** — Nextflow 26.x rejects `def` at config top level when the file is merged with other configs (e.g. `slurm_singularity.config`). Always inline the escalation map inside the closure.

## Config Inheritance

```
nextflow.config → configs/base.config (always loaded)
  ├── configs/local.config
  ├── configs/local-gpu.config
  ├── configs/slurm.config
  ├── configs/slurm_singularity.config
  └── configs/test.config
```

## DSL2 Validation Checklist

When reviewing `.nf` files in this repo, run through these checks (see `references/dsl2-syntax-complete.md` for full detail):

### Must-Pass (❌ FAIL if violated)
1. **Top-level declarations** — Only `include`, `process`, `workflow` allowed at top level; no `def`, `function`, `if/for/switch`
2. **Directive interpolation** — `tag`/`publishDir` must not use input variables (`${meta.id}`); params OK
3. **Container directive form** — Must use lazy closures (`container { params.x }`), not eager GStrings (`container "${params.x}"`), to avoid parse-time undefined-param warnings
4. **No `switch` in workflow** — use `if/else if/else` chains
5. **Stub after script** — `stub:` must follow `script:`, never precede
6. **Escape `$` in R templates** — see Groovy Template Escaping section
7. **Every process needs a stub block** — required for `-stub-run` CI smoke tests
8. **No `def` at config top level** (Nextflow 26.04+) — inline expressions; mixing `def` with config blocks causes parse errors

### Logical Flow Checks (⚠️ WARNING)
1. Channel type mismatches between workflow `take`/`emit` declarations
2. Missing parameter declarations in `nextflow_schema.json`
3. Process labels not defined in profile configs
4. `.map { meta -> [meta, file(meta.path)] }` wrapping for file-mode processes (INGEST_FILE, INGEST_METADATA_FILE)

### Convention Checks (ℹ️ INFO)
1. Naming: `snake_case` dirs, `UPPER_SNAKE_CASE` process/workflow names
2. File naming (`.config`, `.md`, `.nf` patterns)
3. Config inheritance: params in `base.config`, not duplicated in profile configs

### Key Nextflow 26.04.0 Parser Bug
`onComplete:` as a named closure sibling of `main:` fails if the `main:` body contains any **list literal** (`['a', 'b']`) — even `def l = ["a"]`. The DSL2 parser emits `Unexpected input: ':'` when it encounters `onComplete:`. Workaround: restructure into two workflow blocks. See `references/dsl2-syntax-complete.md` for the exact restructure pattern.

### `gpu = 1` Directive Is Ignored
Nextflow core has a `gpu` directive for process resource requests, but without the NF-Core GPU plugin loaded, Nextflow emits a warning and ignores it entirely. The correct pattern in GoodWorkflows is to use `label: 'gpu_long'` on the process and let the profile's `withLabel: 'process_gpu'` block handle GPU allocation (`--gres=gpu:1` in SLURM, `--gpus all` in Podman). Never add bare `gpu = 1` to a process's directive block — it silently does nothing.

## Pre-Commit Validation Checklist

Run these checks before any non-trivial commit, push, or CI submission. This consolidates findings from DSL2 validation, Python template runtime, template parity, and ShellCheck into one entry point.

### DSL2 & Config
1. **No top-level `def`/`switch`** — only `include`, `process`, `workflow` at top level in `.nf` files; no `switch` in workflow bodies
2. **`stub:` after `script:`** — ordering matters; every process needs a stub block
3. **Container directives use lazy closures** — `container { params.x }`, not `container "${params.x}"`
4. **Config `withName` blocks** — no `container = { params.x }` lines; module-level closures handle it
5. **No `def` at config top level** — inline expressions in `.config` files (Nextflow 26.04+)
6. **No `workDir` in included configs** — `run.sh` launchers pass `-work-dir` explicitly
7. **Every `test` profile includes `base.config`** before other profile configs
8. **CI memory overrides** — CI profiles inheriting `local-gpu.config` must cap GPU-era memory (e.g. `process_nmf_vae` → ≤4 GB for 15.6 GB Actions runners)
9. **Process memory ≤ available RAM** — override in `local-gpu.config` if base.config requests > 31 GB

### Templates (Python/R/Shell)
10. **NUMBA env var** — `# NUMBA_CACHE_DIR=/tmp` at top of any Python template with scanpy/scipy before other imports
11. **No `\\n`/`\\t` in strings** — use `chr(10)`/`chr(9)` in template files to survive Groovy rendering
12. **`obs→str` coercion before `write_h5ad()`** — unconditional loop, not `dtype != object` guard
13. **R `[[ ]]` not `$`** — grep for bare `$` outside `${...}`: `grep -Pn '(?<!\\\\)\\$(?![{])' modules/**/templates/*.r modules/**/templates/*.py`
14. **No `${collected_paths}` interpolation** — use `list.dirs()` glob instead of `strsplit`
15. **No `file.copy(from, to)`** when staged file and output share same name — use `readRDS()` directly
16. **No `..keep_cols`** on Seurat data.frames — use `df[, cols, drop = FALSE]`
17. **No `inputSeurat`** in tcrClustR calls — removed in current API
18. **No bare `$"` or `$V1`** patterns — Groovy token errors; escape as `\\$`
19. **Verify template bytes with `od -c`** when fix doesn't take effect; never use `read_file()`+`write_file()` on templates
20. **ShellCheck** — `VAR="value"` not `VAR=value` (SC2209); run on all modified `.sh` files

### Images & Workflows
21. **Container images** — every `*_container` param appears in ALL three lists: `scripts/image-manifest.txt`, `template/gw/setup.sh`, `scripts/ci/cache_container_images.sh`
22. **Workflow lists** — `main.nf` `supportedWorkflows` is source of truth; sync with `template/gw/run.sh`, `template/cluster/run.sh`, `check_workflows.sh`, `fetch_example_data.sh` "Next" block
23. **Docusaurus docs** — update `docs/workflows/<name>.md`, `docs/index.md` table, `docs/parameters.md` `--workflow` enum, `mkdocs.yml` nav for new workflows
24. **Apptainer env vars** — `SINGULARITYENV_*` → `APPTAINERENV_*` mapping in `slurm.apptainer-before.sh`

# Groovy Template Escaping in `.r`/`.R`/`.py` Files

Nextflow's `template` directive processes files through Groovy's GStringTemplateEngine, which interpolates `$` expressions BEFORE the file reaches R/Python. This causes subtle failures that look like runtime errors but are actually parse-time Groovy errors.

## How Nextflow Template Processing Works

1. Template file is read as a Groovy GString (like a double-quoted string with `${}`)
2. `${...}` expressions (Nextflow variable substitution) are evaluated eagerly
3. `$identifier` is also treated as a variable reference (e.g., `$seurat` tries to resolve Groovy variable `seurat`)
4. `\$` outputs a literal `$` in the rendered result
5. The rendered text is then passed to R/Python for execution

## Known Failure Patterns and Fixes

### Pattern 1: `$identifier` in R code (most common)

R uses `$` for list/column access. Groovy interprets this as a variable reference.

```r
# ❌ FAIL — Groovy tries to resolve variable `V1`, `seurat`, `cluster_summary`
feat <- fread("features.tsv")$V1
seurat_obj <- seurat_obj$seurat
length(dp$cluster_summary$cluster)

# ✅ PASS — escape $ with backslash so Groovy outputs literal $
feat <- fread("features.tsv")$\V1
seurat_obj <- seurat_obj\$seurat
length(dp\$cluster_summary\$cluster)
```

Affected constructs:
- `data.table::fread(...)$V1` — column access
- `obj$metadata_col` — S3 list access
- `dp$field$subfield` — nested list access
- `seurat_obj@misc$TCR_Dirichlet` — S4 slot sub-access

**All must use `\$` to escape the dollar sign.**

### Pattern 2: `$"` in R string literals (Groovy token error)

When `$` is followed by a `"` inside an R string, Groovy's parser chokes.

```r
# ❌ FAIL — $ followed by " causes token recognition error
count_dirs <- grepl("_counts$", dir)

# ✅ PASS — escape the $ so Groovy outputs literal $
count_dirs <- grepl("_counts\$", dir)
```

Affected constructs:
- R regex patterns using `$` anchor: `grepl("pattern$", x)`
- R `sub`/`gsub` with `$`: `sub("suffix$", "", x)`
- Any string containing `$` before a `"` character

### Pattern 3: `$\` (backslash after dollar) — wrong escape order

This happens when someone tries to escape `$` but puts the backslash AFTER the dollar instead of BEFORE it.

```r
# ❌ FAIL — Groovy token recognition error at backslash
feat <- fread("features.tsv")$\V1

# ✅ PASS — backslash BEFORE dollar
feat <- fread("features.tsv")$\V1
```

### Pattern 4: `$` in multi-line R heredocs within Nextflow template files

The same rules apply inside `<<'REOF'` heredocs in `.nf` files. All bare `$` must be escaped.

```groovy
script:
"""
Rscript -e '
df$column <- value     # ❌ FAIL — Groovy tries to resolve $column
df\$column <- value    # ✅ PASS — escaped
'
"""
```

### Pattern 5: Container directives — eager GString vs lazy closure

Module `main.nf` container directives that use GString interpolation trigger "Access to undefined parameter" warnings at parse time, even if the param is defined later in the config.

```groovy
// ❌ FAIL — eager GString evaluated at parse time, before config merge
container "${params.milton_container}"

// ✅ PASS — lazy closure evaluated at task execution time, after all configs merged
container { params.milton_container }
```

**Rule:** ALL module container directives must use closure form `container { params.x }`. This is a MUST-PASS review item for any new module.

### Pattern 6: Config withName container closures — still evaluated eagerly

Nextflow 26.04 evaluates `params.x` inside config `withName`/`withLabel` closures at parse time, even though the closure syntax is "lazy". This triggers the same WARN messages.

```groovy
// ❌ FAIL — Nextflow 26.04 evaluates params.x at parse time even in closures
process {
    withName: 'GEX_MERGE_COUNTS' {
        container = { params.milton_container }   // triggers WARN
    }
}

// ✅ PASS — remove container assignment from withName; module-level closure handles it
process {
    withName: 'GEX_MERGE_COUNTS' {
        // no container line — module main.nf has container { params.x }
    }
}
```

**Rule:** Do NOT add `container = { params.x }` to config `withName`/`withLabel` blocks. Module-level closures are sufficient and don't trigger warnings. Use `withName` only for resources (cpus, memory, time, label).

## Verification

Before committing any template file changes, check for bare `$` that aren't Nextflow `${...}`:

```bash
# Check R/Python template files (finds bare $identifier — must be escaped as \$)
find modules -path '*/templates/*.r' -o -path '*/templates/*.R' -o -path '*/templates/*.py' | xargs grep -n '\$[A-Za-z_]' 2>/dev/null

# Exclude Nextflow substitutions (${...}) — these should be:
#   ${params.xyz}   — intentional Nextflow subs
#   ${meta.id}      — intentional Nextflow subs
# Everything else is likely a Groovy template bug and needs \$ escaping.
```

## Container Image Pull Timeouts

When adding new workflow containers to `check_workflows.sh --real`, the first run pulls images from ghcr.io. Large images (tcrclustr, mil-ton) can take 30-60s to pull over a cold connection. This is normal — subsequent runs use the local cache. If a workflow fails at the container pull step, it's usually not a code bug; just re-run.

## Quick Reference: `$` Escaping Table

Nextflow processes template files (.r, .py, .sh) with Groovy's GStringTemplateEngine.
Every bare `$` not inside `${...}` is a Groovy variable reference, NOT R/Python syntax.

| Context | Broken (Groovy fails) | Fixed (Groovy produces correct output) | Where |
|---|---|---|---|
| data.table column access | `$V1` | `\$V1` | `merge_gex.r` |
| R list accessor | `$sample_id`, `$barcode`, `$seurat` | `\$sample_id`, `\$barcode`, `\$seurat` | `merge_gex.r`, `quantify_tcr.R` |
| S4 slot name | `$TCR_Dirichlet`, `$cluster_summary` | `\$TCR_Dirichlet`, `\$cluster_summary` | `quantify_tcr.R` |
| R regex anchor (end of string) | `"_counts$"` | `"_counts\$"` | `merge_gex.r` |
| data.table `..` prefix on data.frame | `df[, ..keep_cols]` | `df[, keep_cols, drop=FALSE]` | `quantify_tcr.R` |
| file.copy self-copy | `file.copy(from, to)` where `from==to` | `readRDS(from)` directly | `ingest_file.r` |
| Bioconductor `%||%` operator | `x %||% y` | `if (!is.null(x)) x else y` | various (rdiscvr lacks `rlang`) |

**Detection command (must include `.R` — uppercase — to catch files like `join_seurat.R`):**
```bash
find modules -path '*/templates/*.r' -o -path '*/templates/*.R' -o -path '*/templates/*.py' | xargs grep -Pn '(?<!\\\)\\$(?!\\{)' 2>/dev/null
```

This finds `$` not preceded by `\` and not followed by `{` — all such occurrences
in Nextflow template files are bugs unless they are inside `${...}` substitutions.

See [`references/template-pitfalls.md`](references/template-pitfalls.md) for
full reproduction recipes and error messages.

| Template code | Groovy sees | R/Python gets | Status |
|---|---|---|---|
| `$V1` | Variable `V1` | Error | ❌ |
| `\$V1` | Escaped `$` + `V1` | `$V1` | ✅ |
| `$\V1` | `$` + invalid escape `\V` | Error | ❌ |
| `$seurat` | Variable `seurat` | Error | ❌ |
| `\$seurat` | Escaped `$` + `seurat` | `$seurat` | ✅ |
| `$cluster_summary` | Variable `cluster_summary` | Error | ❌ |
| `\$cluster_summary` | Escaped `$` + `cluster_summary` | `$cluster_summary` | ✅ |
| `"_counts$"` | `$` + `"` — token error | Error | ❌ |
| `"_counts\$"` | Escaped `$` + `"` | `"_counts$"` | ✅ |
| `meta$sample_id` | Variable `sample_id` | Error | ❌ |
| `meta\$sample_id` | Escaped `$` + `sample_id` | `meta$sample_id` | ✅ |

## Python Template Runtime Pitfalls

Python templates (`.py`, `.r`, `.sh` via `template 'file'`) run inside Apptainer/Singularity containers — some bugs are specific to that environment and never surface in local dev. See `references/python-template-runtime.md` for full detail.

### 1. Numba JIT Cache Failure
Apptainer containers mount a read-only squashfs filesystem — Numba's JIT cache cannot write alongside the source files, so the `@vectorize` decorator's `enable_caching()` fails at import time. The fix is to redirect the cache to `/tmp`.
- **Fix:** Set `NUMBA_CACHE_DIR=/tmp` as the first lines of the Python template (before any Numba-using imports)
- **Files affected:** `integrate.py`, `merge_gex.r` (any template that transitively imports `umap` → `pynndescent`)
- **⚠️ Do NOT use `environment` directive in config files** — it does not exist in Nextflow 26.04 and causes Groovy parse errors. The Python env-var approach is the only reliable mechanism.

### 2. Groovy Escape Stripping — `\\\\n` → Literal Newline
When Nextflow renders `template 'file.py'`, Groovy processes `\\\\n` → actual newline and `\\\\t` → actual tab **before** the text reaches Python.
- **Fix:** Use `chr(10)` / `chr(9)` in string literals instead of `\\\\n` / `\\\\t`
- **Applies to:** `.py`, `.r`, `.sh` template files

### 3. R Column Access — Use `[[]]` Not `$`
- `seurat_obj$RNA` → `seurat_obj[["RNA"]]`
- `df$celltype` → `df[["celltype"]]`
- `metadata_df$sample_id <- value` → `metadata_df[["sample_id"]] <- value`

## Repo Monitoring (Cron Job)

A cron job checks for new commits on Mon/Wed/Sat. See `goodworkflows-monitor` for the full run book. Summary:

1. Fetch commits since last check via GitHub API (`~/.hermes/cron/goodworkflows_last_check.txt`)
2. For each new commit, fetch the changed files via GitHub API
3. For each `.nf` change, validate DSL2 syntax (see DSL2 Validation Checklist above)
4. For config changes, verify param consistency across profiles
5. For script changes, check ShellCheck compliance
6. Generate a report: commit SHA, message, changed files, DSL2 status, logical flow, conventions
7. Log key findings to memory; report if critical issues found

**Rule:** You are **recording** changes, not implementing them. The user implements. Be concise — actionable info only, not verbose diffs. If a commit touches workflow logic, pay extra attention to channel types and parameter flows.

## Template Parity (gw/ vs cluster/)

Two template directories must stay functionally synchronized. See `references/template-parity.md` for the full checklist.

| Directory | Profile | Runtime |
|---|---|---|
| `template/gw/` | `local_gpu` | Podman + `--gpus all` |
| `template/cluster/` | `slurm_singularity` | Apptainer SIF from cache |

### What Must Stay in Sync
1. **Container image lists** — `scripts/image-manifest.txt` (source of truth), `template/gw/setup.sh`, `scripts/ci/cache_container_images.sh`
2. **Workflow lists** — `main.nf` `supportedWorkflows` (source of truth), `template/gw/run.sh` VALID_WORKFLOWS, `template/gw/check_workflows.sh` (auto-discovers from main.nf), `README.md` workflow table, `template/gw/README.md` workflow table
3. **Module container directives** — ALL module `main.nf` container directives must use closure form `container { params.x }`, NOT eager GString `container "${params.x}"`. This is a MUST-PASS review item for any new module.
4. **Config withName container overrides** — Do NOT add `container = { params.x }` to config `withName`/`withLabel` blocks; Nextflow 26.04 evaluates them eagerly at parse time, triggering "Access to undefined parameter" warnings. Module-level closures handle it. Use `withName` blocks only for resources (cpus, memory, time, label).
5. **NF_ARGS parity** — core Nextflow arguments should be identical in both `run.sh` files; profile-specific args differ
6. **PIPELINE_ROOT detection** — auto-detect logic must be consistent

### Expected Intentional Divergences (Do NOT "fix")
- Profile (`local_gpu` vs `slurm_singularity`), container runtime, image pre-pull strategy
- LabKey creds (required in cluster, not local), SLURM `#SBATCH` headers
- Nextflow binary path (`nextflow` in PATH vs `NEXTFLOW_BIN` env var)
- Color output (ANSI locally, plain text on SLURM logs)

## check_workflows.sh — Serial Workflow Test Runner

`template/gw/check_workflows.sh` runs every workflow in sequence under stub-run (default) or real (--real) mode.

### Auto-Discovery
The script automatically reads `main.nf` → `supportedWorkflows` and registers unknown workflows with sensible defaults (samplesheet.csv, no extra flags). You only need to add a WORKFLOW_REGISTRY entry if the workflow needs a non-default samplesheet or extra arguments. This means adding a workflow to main.nf automatically includes it in the test runner.

### Run Directory & Latest Symlink

Both `template/gw/run.sh` and `template/gw/check_workflows.sh` create timestamped run directories under `template/gw/runs/<workflow>_<timestamp>/` with `logs/`, `outputs/`, and `work/` subdirectories. After creating the run directory, they update `template/gw/runs/latest` as a symlink to the newest run dir:

```
template/gw/runs/latest → .../runs/integration_20260512_204337/
template/gw/runs/latest/logs/nextflow.log
template/gw/runs/latest/outputs/
```

This gives a consistent landing spot for debugging. The symlink is updated at the start of each run, so it points to the run dir even if the pipeline crashes partway through.

### Pre-Flight Checks
- Nextflow availability and test profile config load
- Workflow list parity between registry and main.nf
- Samplesheet existence and column validation (expected_col field)
- File existence for path-based samplesheet rows

### Two Modes

- **Stub-run (default):** `nextflow run -stub-run -profile test` — quick pipeline compilation validation, no containers needed. Good for pre-commit / CI gate.
- **Real (--real):** `bash run.sh --workflow <name>` — actual Podman-backed execution on the toy RDS datasets. Requires containers pulled (`bash setup.sh`) and test data generated (`bash fetch_example_data.sh`).

The registry entries (WF_STUB / WF_REAL) define per-workflow flags for each mode. For example, `tcr_epitope` adds `--binding_model_path tcr_epitope_models` in real mode but not stub.

### When a Workflow Fails Stub-Run
- If the check_workflows.sh registry has `expected_col` set but the samplesheet is missing it (e.g., `gex_mil` needs `SubjectId`), a pre-flight [INFO] warns before the run. See `references/template-parity.md` for specific workflow column requirements.
- If the samplesheet file doesn't exist (e.g., `tcr_epitope_samplesheet.csv` hasn't been generated by fetch_example_data.sh), it's a pre-flight [WARN] and the workflow is still attempted.

### Common --real Failure: Stale Test Data
`check_workflows.sh --real` runs against test data generated by `fetch_example_data.sh`. If the test metadata CSVs (`template/gw/data/*_metadata.csv`) are stale — just 8-byte headers with only `cDNA_ID` and no RIRA cell-type columns — the TABULATE process fails with:
```
Error: No cell-type columns found in metadata. Expected at least one of: RIRA_Immune.cellclass, RIRA_TNK_v2.cellclass, RIRA_Myeloid_v3.cellclass
```

**Causes:**
- `fetch_example_data.sh` hasn't been run after a repo clone or tree reset
- A previous stub-run (`INGEST_METADATA_FILE`'s stub writes `printf 'cDNA_ID\n'`) or incomplete real run overwrote the data dir CSVs with placeholders
- The pbmc3k RDS files exist but `gen_metadata_csv()` in `fetch_example_data.sh` failed silently

**Fix:** Re-run `bash fetch_example_data.sh` from `template/gw/` to regenerate proper metadata CSVs with cell-type columns. The script extracts `RIRA_Immune.cellclass`, `RIRA_TNK_v2.cellclass`, `RIRA_Myeloid_v3.cellclass` from the pbmc3k Seurat objects.

**Check current state:**
```bash
wc -l template/gw/data/PBMC_*_metadata.csv
# Should show 1000+ rows per file (data + header). If 1 line = header-only = stale.
head -3 template/gw/data/PBMC_HUMAN_metadata.csv
# Should show columns including RIRA_Immune.cellclass, RIRA_TNK_v2.cellclass, etc.
```

## Tracked vs Generated Files (.gitignore Policy)

Only scripts and reference files are tracked in git. All generated data, run outputs, cache directories, and binary test data are gitignored.

## Doc Review Convention

After every code change (template, config, or module), review the corresponding user-facing docs and parity files for accuracy. The user expects this check proactively. Specifically:

1. **`docs/data-formats.md`** — if the output format of any process changed (X dtype, column names, file names, normalization state), update the description.
2. **`docs/usage.md`**, **`docs/parameters.md`** — if params or workflow capabilities changed.
3. **`memory-bank/*.md`** — internal AI-facing docs kept alongside the code. These go stale fast; update them with each code change.
4. **`template/gw/` vs `template/cluster/` parity** — verify that template files are shared (template changes affect both profiles) and that profile-specific divergences (config, run.sh) are intentional. See `references/template-parity.md` for the full checklist.
5. **README.md** — check workflow tables and container image lists.
6. **`scripts/image-manifest.txt`** — add new container images.

**Rule of thumb:** If you touched a `.nf`, `.py`, `.r`, or `.config` file, something in the docs or memory-bank is now out of date. Find and fix it.

### Template Directory (`template/gw/`)

**Kept in git (scripts only):**
- `fetch_example_data.sh` — generates example RDS data + samplesheets
- `setup.sh` — pulls container images
- `check_workflows.sh` — serial workflow test runner
- `run.sh` — per-workflow runner
- `README.md` — documentation

**Untracked (everything else gitignored):**
- `data/` — RDS/CSV generated by `fetch_example_data.sh`
- `runs/` — timestamped run output dirs (logs, outputs, work/)
- `.nextflow*` — Nextflow cache and log files
- `*_samplesheet.csv` — workflow-specific generated samplesheets
- `samplesheet.csv`, `tabulate_samplesheet.csv` — reference samplesheets with local absolute paths (regenerated by fetch_example_data.sh)

### Test Data (`test-data/`)

- `test-data/**/*.rds` — ignored (too large for git; SMOKE.rds was 89MB)
- `test-data/tcr_epitope/` — generated binding model artifacts
- CSV/Fasta files under 50MB remain trackable but all `.rds` files are ignored

### Other Ignored Directories

- `.archs4/` — ARCHS4 GEO metadata cache (large external dataset, ~6GB)
- `work/`, `outputs/`, `logs/`, `runs/` — top-level Nextflow run artifacts
- `testing_space/`, `workspace/` — local dev scratch directories

### If You Add a New Workflow with Test Data

1. Ensure `fetch_example_data.sh` generates the test data (RDS + samplesheet) into `template/gw/data/` or similar
2. Do NOT commit the generated RDS/CSV files — the `.gitignore` patterns above will catch them
3. If the workflow uses a novel samplesheet format, add its name to `check_workflows.sh` registry if non-default samplesheet is needed
4. **TCR workflows (tcr_mil, tcr_epitope) require TCR columns:** The pbmc3k test data (gene expression only) needs synthetic TRA/TRB CDR3 sequences + V/J gene assignments injected via `fetch_example_data.sh` (see the "Injecting synthetic TRA/TRB TCR columns" section). Without this step, QUANTIFY_TCR fails with "Missing required metadata columns: TRA, TRA_V, ..."
5. **INGEST_FILE needs a Seurat RDS, not a raw CSV:** If the test data is a CSV (like `toy_tcr_metadata.csv`), `fetch_example_data.sh` must also generate a minimal Seurat RDS from it. INGEST_FILE uses `readRDS()` for `.rds` files and `fread()`+`CreateSeuratObject()` for `.csv` files — but a TCR metadata CSV is NOT a count matrix. Generate the RDS with:
   ```r
   counts <- Matrix(0, nrow = 1, ncol = nrow(meta))
   rownames(counts) <- "FAKEGENE"
   colnames(counts) <- meta$barcode
   obj <- CreateSeuratObject(counts = counts, meta.data = meta)
   ```
6. **tcrClustR validates V/J genes against an internal database:** Synthetic V/J names (like `TRAV12-2*01`) cause "The following N values were not found in the DB" errors. Set V/J columns to `NA` in the test data to skip validation.

## Environment Debugging: Distrobox / Podman Overlay Symlinks

When you run `which Rscript` and find the binary, but `Rscript -e '...'` fails with `Rscript execution error: No such file or directory`, the cause is often a **stale distrobox-exported symlink** pointing into a Podman overlay layer that only exists while the container is running.

### Detection
Check if the symlink target disappears entirely:
```bash
ls -la $(which Rscript)
# → lrwxrwxrwx ... /home/user/.local/bin/Rscript ->
#      .../containers/storage/overlay/<hash>/diff/usr/local/bin/Rscript
ls -la .../containers/storage/overlay/<hash>/diff/usr/local/bin/Rscript
# → "No such file or directory" — overlay not mounted
```

This happens because distrobox `distrobox-export --bin` creates a symlink from `~/.local/bin/` into the running container's writable overlay layer. When the container stops, the overlay unmounts, and the symlink dangles.

### Fix
```bash
# 1. Remove the stale symlink
rm ~/.local/bin/Rscript

# 2. Install the tool on the host instead, or run inside the container
sudo rpm-ostree install R   # install natively

# OR enter the distrobox and run from inside
distrobox enter <container-name>
```

### Background
Podman stores container writable layers under `~/.local/share/containers/storage/overlay/<hash>/diff/`. Directories like `overlay-images/` and `overlay-layers/` index these. The `db.sql` SQLite database in the same directory maps container IDs to overlay hashes — query it when you need to trace a hash back to its container.

## Research Context

**Domain:** scRNA-Seq in infectious disease studies
**Challenge:** Low sample-size (N<20 subjects), hard-to-estimate parameters
**Approach:** Cellular-scale data density + subject-scale Bayesian inference
**Key interests:** Extended Flexible Dirichlet Multinomial (EFDM), parallel tempering in Julia, cross-species integration

### Research Scanning (Weekly)

A cron job runs weekly to scan for methods, tools, and papers relevant to GoodWorkflows' domain. Run book:

**Primary targets (scan every run):**
1. scRNA-Seq + infectious disease — new analysis methods, benchmarking studies, integration techniques
2. Low sample-size single-cell — Bayesian methods, hierarchical models, subject-level inference from cellular data
3. Cross-species integration — ortholog mapping, multi-species latent spaces, conservation analysis

**Secondary targets (scan every run):**
4. Extended Flexible Dirichlet Multinomial — compositional data, zero-inflated models, cell-type proportion analysis
5. Parallel tempering MCMC — Julia ecosystem, Hamiltonian Monte Carlo variants
6. Cellular data + subject inference — methods that use within-subject cell counts to improve subject-level estimates

**Search strategy:**
```
# Google Scholar / web
"single cell RNA-seq" infectious disease 2025..2026
"single-cell" Bayesian hierarchical "low sample"
"cross-species" OR "multi-species" single-cell integration scRNA-seq
"parallel tempering" Julia MCMC Stan
"Dirichlet multinomial" OR "compositional" single-cell cell-type proportion

# arXiv: q-bio.GN, q-bio.QM, stat.ME
# GitHub: scanpy, anndata, single-cell repos
# Bioconductor / arXiv preprints
```

**Output format:**
```markdown
# Research Scan: YYYY-MM-DD

## TL;DR
- 1-3 sentence summary

## High-Priority Findings
### [Tool/Method]
- What, why relevant, implementation effort, link, prompt snippet

## Secondary Findings
### [Brief]

## No Significant Findings
(include if nothing noteworthy)
```

**For each high-priority finding, generate a ready-to-use prompt:**
```
"Create a Nextflow module for [TOOL] in GoodWorkflows.
- Input: tuple val(meta), path(counts_dir)
- Output: [files]
- Container: [suggested image]
- Process label: process_label
- Stub block: [what to touch]
- Follow repo conventions: snake_case dir, UPPER_SNAKE_CASE process name, stub after script."
```

**Cadence:** Weekly. Short "no significant findings" is fine when warranted.
