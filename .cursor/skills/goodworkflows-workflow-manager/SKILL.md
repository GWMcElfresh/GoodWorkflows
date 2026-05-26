---
name: goodworkflows-workflow-manager
description: Plan and execute GoodWorkflows workflow-manager changes. Use when adding or refactoring saved workflows, modules, launcher templates, samplesheets, CI smoke tests, docs, or when the user asks to manage implementation across GoodWorkflows workflow stages.
---

# GoodWorkflows Workflow Manager

This adapts the Vecinita workflow-manager pattern to GoodWorkflows. The goal is not a generic app build pipeline; it is disciplined evolution of reusable Nextflow workflows.

## Operating Loop

1. Gather context from the closest existing workflow, module, config, docs page, and memory-bank note.
2. Identify the workflow surface touched: DSL2 wiring, module template runtime, launcher scaffold, CI, docs, or generated outputs.
3. Plan the smallest change that keeps `main.nf`, configs, templates, tests, and docs aligned.
4. Implement in dependency order: tests or smoke wrappers first when practical, then DSL2/module code, then launchers/docs.
5. Verify with focused checks and broaden to workflow/module smoke tests when risk warrants.

## GoodWorkflows Stage Mapping

- Requirements: define workflow purpose, samplesheet columns, params, outputs, and compute profile.
- Technical plan: choose module boundaries, channel shapes, process labels, containers, and docs updates.
- Build: implement modules, workflows, templates, configs, launchers, and schemas.
- Verify: run DSL2/stub checks, ShellCheck/script checks, docs build where touched, and template parity checks.
- Evolve: update existing workflows by replacing unshipped branch behavior directly rather than layering shims.
- Hotfix: reproduce from `nextflow.log` or generated `.command.sh`, fix the first root cause, and add a targeted regression check.

## Required Design Choices

- Keep modules independently testable under `tests/modules/`.
- Prefer one responsibility per module. Do not duplicate normalization or densification across pipeline stages.
- Preserve raw sparse count matrices through export, harmonize, and merge stages unless a model stage consumes dense data.
- Use profile resources and process labels instead of embedding environment-specific behavior in templates.
- Treat docs and memory-bank updates as part of the implementation when user-facing behavior changes.

## Handoff Format

When finishing a workflow-manager task, report:

- What changed at the workflow surface level.
- Which verification ran.
- Any skipped checks and why.
- Follow-up risks, especially around real container/HPC execution that stub-run cannot cover.
