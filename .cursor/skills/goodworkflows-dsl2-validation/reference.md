# GoodWorkflows DSL2 Validation Reference

Detailed checks migrated from the retired root `skills/` directory.

## Failure Patterns

| Error or symptom | Likely cause | Fix |
| --- | --- | --- |
| `DataflowVariable (value=null)` | Capturing `process.out.*` inside `.map`, `.combine`, or `.join` closures | Use dual emits, explicit channels, or `.combine()` for global file broadcast |
| `Access to undefined parameter` | Eager container GString such as `container "${params.x}"` | Use `container { params.x }` in module directives |
| `token recognition error at '\'` or bare `$"` | Unescaped `$` in a Groovy-rendered template | Escape as `\$` or use R `[[]]` access |
| `No such property: V1` / `seurat` | R `$` accessor interpreted by Groovy | Use `\$V1`, `\$seurat`, or `[[]]` |
| `SyntaxError: unterminated string literal` in `.command.sh` | Groovy converted `\n`, `\t`, or `\r` before Python ran | Use `chr(10)`, `chr(9)`, or safe escaping |
| `Process requirement exceeds available memory` | Profile resource higher than local runner capacity | Override in the relevant profile |
| Input tuple mismatch | Process expects `tuple val(meta), path(file)` but received `meta` only | Wrap with `.map { meta -> [meta, file(meta.path)] }` |

## Must-Pass DSL2 Checks

- Top level `.nf`: only `include`, `process`, and `workflow`.
- No workflow-level `switch`; use `if/else if/else`.
- `stub:` follows `script:` or `exec:`.
- Every process has a stub output matching real output shape.
- `tag` and `publishDir` do not interpolate input variables.
- Module containers use lazy closures.
- Config files do not use top-level `def` mixed with config blocks.
- Config `withName`/`withLabel` blocks do not assign `container = { params.x }`.

## Workflow Completion Notes

Valid workflow-level scopes are `onStart:`, `onComplete:`, and `onStop:`. Avoid `onError:`.

If `onComplete:` fails to parse near a list literal in `main:`, restructure into a wrapper workflow and keep completion handling in the top-level workflow. This avoids known parser edge cases.

## Label/Profile Cross-Check

When adding labels, verify every label exists in relevant profiles:

```bash
for label in $(grep -rh "label '" modules/ --include='main.nf' | sort -u); do
  echo "=== $label ==="
  for cfg in configs/slurm.config configs/local-gpu.config configs/test.config; do
    found=$(grep -c "withLabel: '$label'" "$cfg" 2>/dev/null || echo 0)
    echo "  $cfg: $found"
  done
done
```

## Shell Traps in Process Scripts

- With `set -euo pipefail`, append `|| true` to expected-empty `grep` pipelines.
- `.netrc` mounts belong only on LabKey ingest processes, not generic file/url/export/tabulate steps.
