---
name: goodworkflows-repo-context
description: GoodWorkflows repository context for a DSL2 Nextflow single-cell workflow manager. Use when working on modules, workflows, configs, docs, templates, CI, SLURM/Apptainer profiles, local Podman runs, or when the user asks how the repo is organized.
---

# GoodWorkflows Repo Context

GoodWorkflows composes reusable single-cell analysis workflows from small DSL2 modules. It targets local development with Podman and HPC execution with SLURM + Apptainer.

## Core Layout

- `main.nf`: thin launcher selected by `--workflow`.
- `workflows/`: saved workflow definitions such as `ingest_export`, `ingest_tabulate`, `integration`, `nmf_vae`, `gex_mil`, `tcr_mil`, and `tcr_epitope`.
- `modules/local/`: single-step DSL2 modules. Directories use `snake_case`; process names use `UPPER_SNAKE_CASE`.
- `configs/`: `base.config` plus profile configs for local, local GPU, SLURM, SLURM Apptainer, and test.
- `template/gw/`: local workflow-manager scaffold with setup, data fetch, run, and serial workflow checks.
- `template/cluster/`: cluster-oriented run scaffold when present; expected to stay functionally aligned with `template/gw/`.
- `docs/`, `memory-bank/`, `README.md`: user-facing and AI-facing documentation that should be updated with behavior changes.

## Workflow Goals

Preserve these goals when changing code:

- Workflows should be modular, independently smoke-testable, and runnable through `main.nf --workflow <name>`.
- CI should validate DSL2 wiring through `-profile test -stub-run` without real containers or heavy computation.
- HPC runs should use Apptainer SIF cache behavior and profile resources rather than ad hoc command-line mutations.
- Local workflow-manager scripts should create predictable run directories with logs, outputs, work dirs, and a latest pointer where supported.

## Important Domain Invariants

- Ingest modes are mutually exclusive per sample row: LabKey `output_file_id`, `url`, local Seurat `path`, or standalone `metadata_path`.
- File-mode processes expecting `tuple val(meta), path(file)` must receive wrapped tuples: `.map { meta -> [meta, file(meta.path)] }`.
- HARMONIZE, MERGE, and EXPORT modules should preserve raw sparse counts. Training/integration modules own normalization and densification.
- Every process needs a `stub:` block so smoke tests can compile and run without full data.

## Before Editing

Read the closest existing module, workflow, config, or docs page before introducing a new pattern. Prefer the established local conventions over generic Nextflow or nf-core defaults unless the repo already follows them.
