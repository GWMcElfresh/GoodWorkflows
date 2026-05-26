# GoodWorkflows Verification Reference

Migrated from the retired root `skills/` directory.

## Pre-Commit / Pre-Handoff Checklist

### DSL2 and Config

- no top-level `def` or workflow-level `switch`
- `stub:` after `script:` or `exec:`
- module containers use lazy closures
- config `withName`/`withLabel` blocks do not assign param containers
- no top-level config `def`
- every `test` profile path includes base config expectations
- process memory fits the intended runner or has profile overrides

### Templates

- `NUMBA_CACHE_DIR=/tmp` before Numba-triggering imports
- no unsafe raw `\n`/`\t` strings in Groovy-rendered Python templates
- `obs` columns coerced to strings before `write_h5ad()`
- R templates prefer `[[]]` over `$`
- no bare `$` outside `${...}` in rendered templates
- no self-copy of staged files

### Images and Workflows

- image manifest, local setup, and CI cache lists agree
- `main.nf` workflow list agrees with launchers, CI, schema, docs, and memory-bank
- docs are updated for changed params, outputs, workflow capability, or data format
- generated run artifacts are not included as source changes

## Useful Commands

```bash
nextflow run main.nf -profile test -stub-run --workflow <name> --input <samplesheet>
bash -n template/gw/run.sh
bash -n template/gw/check_workflows.sh
mkdocs build --strict
```

Use ShellCheck when available for shell scripts.
