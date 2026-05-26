---
name: goodworkflows-dsl2-validation
description: Validate GoodWorkflows Nextflow DSL2 modules, workflows, and configs. Use when editing .nf or .config files, reviewing workflow wiring, fixing Nextflow parser/runtime errors, adding modules, or preparing stub-run CI validation.
---

# GoodWorkflows DSL2 Validation

Use this skill for every `.nf` or `.config` edit.

## Must-Pass Checks

1. Top level `.nf` declarations are only `include`, `process`, and `workflow`.
2. No `switch` blocks inside workflow bodies; use `if/else if/else`.
3. `stub:` appears after `script:` or `exec:` and exists for every process.
4. Process `container` directives that read params use closure form: `container { params.some_container }`.
5. Config `withName` and `withLabel` blocks do not set `container = { params.x }`; module-level closures handle containers.
6. `.config` files do not define top-level `def` values that mix with config blocks.
7. `tag` and `publishDir` do not interpolate input variables such as `${meta.id}`.
8. Workflow-level completion scopes use valid DSL2 scopes only: `onStart:`, `onComplete:`, `onStop:`.

## Template Interaction Checks

Nextflow templates are Groovy-rendered before R, Python, or shell runs.

- Escape bare `$` in `.r`, `.R`, `.py`, and `.sh` templates unless it is an intentional `${...}` Nextflow substitution.
- Prefer R `[[]]` column/list access in templates to avoid `$` escaping churn.
- Avoid raw `\n`, `\t`, and `\r` in Python template string literals; use `chr(10)`, `chr(9)`, or double escaping where appropriate.
- After escaping changes, clear stale Nextflow work dirs before assuming a fix failed.

## Channel and Parameter Checks

- Match `take:` and `emit:` names between upstream and downstream workflows.
- Wrap local file inputs for processes declared as `tuple val(meta), path(file)`.
- Keep `params` defaults in `configs/base.config`; profile configs should override resources, executors, and runtimes.
- Every process label used in modules should have resources in relevant profiles.

## Verification

Prefer the narrowest useful check first, then broaden:

```bash
nextflow run main.nf -profile test -stub-run --workflow <workflow> --input <samplesheet>
```

For module wrappers, use the matching file under `tests/modules/` when available.
