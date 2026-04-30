# Conventions

> **Syntax Reference:** For Nextflow DSL2 syntax details (comments, declarations, statements, expressions, operators, deprecations), see [`nextflow_synatx.md`](nextflow_synatx.md).

## File Naming

| Type | Convention | Examples |
|---|---|---|
| Nextflow modules | `snake_case` directories, `main.nf` entry | `gene_harmonize/main.nf`, `ingest_metadata/main.nf` |
| Nextflow workflows | `snake_case.nf` | `integration_pipeline.nf`, `ingest_export.nf` |
| Config files | `lowercase.config` or `lowercase.profile.config` | `base.config`, `slurm_singularity.config` |
| Shell scripts | `snake_case.sh` | `slurm_nextflow.sh`, `slurm_sync_repo.sh` |
| Documentation | `kebab-case.md` | `ingest-export.md`, `data-formats.md` |
| Process names | `UPPER_SNAKE_CASE` | `INGEST`, `EXPORT_COUNTS`, `GENE_HARMONIZE` |
| Workflow names | `UPPER_SNAKE_CASE` | `INTEGRATION_PIPELINE`, `INGEST_EXPORT_PIPELINE` |

## Config Inheritance Pattern

```
base.config          ← Always loaded (nextflow.config includes it)
  ├── local.config   ← -profile local
  ├── slurm.config   ← -profile slurm
  ├── slurm_singularity.config ← -profile slurm_singularity
  └── test.config    ← -profile test
```

- `base.config` sets all `params` defaults and `workDir`
- Profile configs override process resources, executor, and container runtime
- Never duplicate params between base and profile configs

## Parameter Passing

- **CLI:** `--param_name value` (Nextflow convention)
- **Config:** `params { param_name = value }`
- **Required params validated in `main.nf`:** `--labkey_base_url`, `--labkey_folder`, `--input`
- **Sensitive values:** Never in params — use env vars or `.netrc` mounts

## Process Label Conventions

Every process has a label matching its resource profile:

| Label | Used By |
|---|---|
| `process_ingest` | INGEST, INGEST_METADATA |
| `process_export` | EXPORT_COUNTS |
| `process_harmonize` | GENE_HARMONIZE |
| `process_tabulate` | TABULATE |
| `process_gpu` | SCMODAL_INTEGRATE |

## Stub Blocks

Every process MUST have a `stub:` block that creates the expected output files (even if empty/touch). This enables `-stub-run` for CI smoke tests.

## Channel Patterns

- **Per-sample channels:** `tuple val(meta), path(file)` — meta is a map with `id`, `output_file_id`, `species`
- **Collected channels:** Use `.collect()` to gather all per-sample outputs into a single list before passing to aggregation processes (GENE_HARMONIZE, TABULATE)
- **Samplesheet parsing:** Each workflow defines its own `build*SamplesChannel()` function

## Nextflow 26.04.0 Process-Scope & Top-Level Constraints

> **IMPORTANT:** In Nextflow DSL2, **all variable assignments (`def foo = ...`), function definitions, and logic (e.g., `if`, `for`, etc.) must be placed inside a `workflow { ... }`, `process { ... }`, or function block.**
> 
> Top-level statements (outside of these blocks) are forbidden and will cause errors like:
> 
>     Statements cannot be mixed with script declarations -- move statements into a process, workflow, or function
> 
> Only `include`, `process`, and `workflow` blocks are allowed at the top level.

> **Process-scope directives** (`tag`, `publishDir`, etc.) cannot interpolate input variables (e.g., `${meta.id}`) because they are evaluated before the `input:` block. Use only static or global values in these directives.

Nextflow 26.04.0 enforces that **process-scope directives** (`tag`, `publishDir`) are evaluated **before** the `input:` block is parsed. Any GString interpolation of an input variable (like `${meta.id}`) in those directives will fail with `No such variable: meta`.

### Rules

- **`tag`**: Must use static string literals only (e.g., `tag 'ingest'`, not `tag "${meta.id}"`)
- **`publishDir`**: Must not reference input variables in the path (e.g., `publishDir "${params.outdir}/ingest"`, not `publishDir "${params.outdir}/ingest/${meta.id}"`)
- **`output:` block**: GString interpolation of input variables remains valid here (e.g., `path("${meta.id}.rds")` is fine)
- **`script:` block**: GString interpolation of input variables remains valid here

### Affected Modules (fixed 2026-04-29)

| Module | Before | After |
|---|---|---|
| INGEST | `tag "${meta.id}"`, `publishDir ".../ingest/${meta.id}"` | `tag 'ingest'`, `publishDir ".../ingest"` |
| INGEST_METADATA | `tag "${meta.id}"`, `publishDir ".../ingest/${meta.id}"` | `tag 'ingest-metadata'`, `publishDir ".../ingest"` |
| EXPORT_COUNTS | `tag "${meta.id}"`, `publishDir ".../counts/${meta.id}"` | `tag 'export-counts'`, `publishDir ".../counts"` |

### Consequence: Flattened Output Layout

Output files are now published directly into the top-level publish directory (e.g., `outputs/ingest/SAMPLE_01.rds`) rather than nested in per-sample subdirectories (e.g., `outputs/ingest/SAMPLE_01/SAMPLE_01.rds`). Smoke test path assertions must match this flattened layout.

## Error Handling

- **SLURM:** Retry on exit 1 (up to 3 attempts with jitter), retry on 125/137 (up to 5 attempts)
- **Local:** Retry on OOM (exit 137) with increasing memory (`8.GB * task.attempt`)
- **GPU guard:** `INTEGRATION_PIPELINE` errors if executor is local and `--scmodal_use_cpu` is not true

## Commit Style

- Descriptive, imperative mood
- Reference workflow or module affected
- Keep commits focused (one logical change per commit)

## Generated Files (Never Edit)

- `site/` — MkDocs build output
- `.nextflow/` — Nextflow cache
- `work/` — Nextflow work directory
- `outputs/` — Published pipeline results
- `logs/` — Nextflow reports and SLURM logs
- `test-results/` — CI test artifacts
- `.ci/docker-cache/` — CI container cache