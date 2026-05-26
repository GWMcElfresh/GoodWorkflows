---
name: 07-build
description: Implement GoodWorkflows planned changes. Use to edit workflows, modules, templates, configs, launchers, docs, tests, memory-bank, and CI according to an accepted technical plan.
---

# 07 Build

Read state and confirm prerequisites. Follow the accepted technical plan.

## Build Order

1. Tests or smoke wrappers when practical.
2. DSL2 modules/workflows/configs.
3. Runtime templates.
4. Launchers, image lists, schema, CI.
5. Docs, README, and memory-bank updates.

## Requirements

- Load `goodworkflows-dsl2-validation` before `.nf` or `.config` edits.
- Load `goodworkflows-template-runtime` before template edits.
- Load `goodworkflows-template-parity` before launcher/image/CI edits.
- Preserve unrelated user changes.
- Do not edit generated outputs as source.

## Output

Update state with changed artifacts and next verification target. Do not claim completion until `08-verify-build` runs or is explicitly skipped.
