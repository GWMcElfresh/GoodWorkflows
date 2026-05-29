---
name: 09-qa
description: Run broader GoodWorkflows quality checks after focused build verification. Use before implementation sign-off, release readiness, or PR creation.
---

# 09 QA

Broaden beyond the immediate changed file.

## QA Areas

- Shell scripts under `template/`, `scripts/`, and configs.
- Python tests under `tests/` when Python/MCP behavior changed.
- `mcp-server` build/tests when MCP workflow generation changed.
- Docs generation and `mkdocs build --strict` when docs, schema, or workflow docs changed.
- Parity between workflow lists, image manifests, launchers, docs, and memory-bank.

## Workflow list parity (required when launchers or main.nf changed)

```bash
bash scripts/ci/check_workflow_parity.sh
```

This compares `main.nf` `supportedWorkflows` to:

- `template/gw/run.sh` `VALID_WORKFLOWS` (errors on mismatch)
- `nextflow_schema.json` workflow enum (errors on mismatch)
- `.github/workflows/ci.yml` smoke matrix (warns by default; `--strict-ci` to fail)
- `template/gw/check_workflows.sh` `register` entries (errors on stale names)
- Registry samplesheet paths resolvable from `template/gw` cwd

## Output

Write a QA summary with exact pass/fail/skipped status. Update verification log and open issues.
