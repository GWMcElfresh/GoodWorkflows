---
name: 07-build
description: Implement GoodWorkflows planned changes. Use to edit workflows, modules, templates, configs, launchers, docs, tests, memory-bank, and CI according to an accepted technical plan.
---

# 07 Build

Read state and confirm prerequisites. Follow the accepted technical plan.

**Prerequisite:** `06-tech-tooling` completed or skipped with user-approved narrow scope.

## Build Order

### New saved workflow (`--workflow` CLI value)

1. Fixtures and samplesheets (`test-data/`, generators, `fetch_example_data.sh`).
2. DSL2 modules, workflows, configs, stubs.
3. Launchers, CI smoke, image manifest, `run.sh` whitelist (same change set as `main.nf`).
4. Runtime templates.
5. Docs, schema, README, memory-bank.

### Other changes

1. Tests or smoke wrappers when practical.
2. DSL2 modules/workflows/configs.
3. Runtime templates.
4. Launchers, image lists, schema, CI.
5. Docs, README, and memory-bank updates.

## Requirements

- Load `goodworkflows-dsl2-validation` before `.nf` or `.config` edits.
- Load `goodworkflows-template-runtime` before template edits.
- Load `goodworkflows-template-parity` before **any** edit to `main.nf` `supportedWorkflows` or launcher surfaces.
- Preserve unrelated user changes.
- Do not edit generated outputs as source.

## Exit criteria

`07-build` is complete only when:

- The launcher & CI plan from `04-tech-plan` is implemented, **or**
- Gaps are recorded in `issue_log` with user acknowledgment.

Do not claim completion until `08-verify-build` runs or is explicitly skipped with reason.

## Output

Update state with changed artifacts and next verification target.
