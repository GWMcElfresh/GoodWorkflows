# Project Brief: GoodWorkflows

## What is this?

GoodWorkflows is a **DSL2 Nextflow** pipeline repository for composing reusable single-cell RNA-seq workflows from small, independently testable modules. It targets **SLURM + Apptainer** HPC systems but also supports local CPU execution for lighter workflows.

**Repository:** [GWMcElfresh/GoodWorkflows](https://github.com/GWMcElfresh/GoodWorkflows)  
**Documentation:** [gwmcelfresh.github.io/GoodWorkflows](https://gwmcelfresh.github.io/GoodWorkflows/)  
**License:** MIT

## Core Purpose

Download single-cell Seurat objects from a LabKey/Prime-seq server, export 10x-like count matrices, harmonize genes across species via ortholog mapping, and train scMODAL to produce a cross-species latent embedding with Leiden clustering.

## Key Stakeholders

- **Bioinformatics researchers** running cross-species scRNA-seq integration on HPC
- **CI/CD maintainers** validating DSL2 wiring via GitHub Actions smoke tests
- **LabKey server operators** providing the data backend

## High-Level Pipeline

```
INGEST → EXPORT_COUNTS → GENE_HARMONIZE → SCMODAL_INTEGRATE
```

Three saved workflows are available via `--workflow`:
1. **`integration`** — Full GPU pipeline (all four stages)
2. **`ingest_export`** — Download + export counts only (CPU)
3. **`ingest_tabulate`** — Download metadata + build subject-level table (CPU)

## Execution Environments

| Environment | Profile | Container Runtime |
|---|---|---|
| Local macOS/Linux | `-profile local` | Podman |
| HPC (SLURM) | `-profile slurm` | Apptainer (SIF cache) |
| CI (GitHub Actions) | `-profile test` | None (stub-run) |