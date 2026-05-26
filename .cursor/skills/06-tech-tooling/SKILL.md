---
name: 06-tech-tooling
description: Prepare GoodWorkflows technical tooling before implementation. Use for CI smoke wrappers, launcher registry updates, image manifests, docs tooling, or test scaffolds needed by a workflow change.
---

# 06 Tech Tooling

Use this stage when implementation requires support files beyond modules/workflows.

## Prepare

- Module wrapper under `tests/modules/` when adding a module.
- Workflow smoke path via `scripts/ci/run_nextflow_smoke_tests.sh`.
- Workflow registry entries in `template/gw/check_workflows.sh`.
- Samplesheet generation in `template/gw/fetch_example_data.sh`.
- Container entries in `scripts/image-manifest.txt`, `template/gw/setup.sh`, and CI cache scripts.
- Docs generation expectations for `scripts/docs/generate_api_docs.sh` and `mkdocs build --strict`.

## Output

Record tooling surfaces in state. If tooling is not needed, mark this stage skipped with rationale.
