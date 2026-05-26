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

## Output

Write a QA summary with exact pass/fail/skipped status. Update verification log and open issues.
