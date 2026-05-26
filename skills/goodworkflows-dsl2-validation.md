---
name: goodworkflows-dsl2-validation
description: "Validate Nextflow DSL2 syntax in GoodWorkflows repo. Checks against DSL2 26.04.0 constraints: top-level declarations, directive interpolation, switch blocks, stub placement, heredoc escaping, and process structure."
version: 1.0.0
metadata:
  hermes:
    tags: [goodworkflows, nextflow, dsl2, validation, syntax, groovy]
---

# GoodWorkflows DSL2 Validation

Use this skill to validate Nextflow DSL2 modules and workflows in the GoodWorkflows repo.

## Priority Order

1. **DSL2 syntax correctness** (must-pass)
2. **Logical flow** (module chaining, channel types, parameter passing)
3. **Naming/config conventions** (nice-to-have)
4. **Config profile parameter alignment** (nice-to-have)

## DSL2 26.04.0 Syntax Checks (Must-Pass)

### 1. Top-Level Declarations

Only `include`, `process`, and `workflow` blocks allowed at top level. No `def`, `function`, `if/for/switch` at top level.

### 2. DSL2 Channel Output Capture: `process.out` in Closures

Never capture `process.out.xxx` inside `.map{}`, `.combine{}`, `.join{}` closures — they resolve to `DataflowVariable (value=null)` at runtime. Use dual-emit or `.combine()` for global file broadcast.

### 3. Directive Interpolation

`tag` and `publishDir` are evaluated BEFORE `input:`. No input variable interpolation (`${meta.id}`). `params.xxx` OK.

### 3B. Container Directive: Lazy Closures vs Eager GStrings

ALL module `container` directives referencing `params.x` MUST use closure form `{ params.x }`, NOT eager `"${params.x}"`. Eager GStrings evaluate at parse time before config merge, triggering "Access to undefined parameter" warnings.

### 3C. Config-Level withLabel Containers

Do NOT add `container = { params.x }` to config `withName`/`withLabel` blocks — Nextflow 26.04 evaluates them eagerly at parse time too. Module-level closures handle it.

### 4. No Switch in Workflow

`switch/case` blocks forbidden inside workflow bodies — use `if/else if/else` chains.

### 5. Workflow Completion Handler

Use `onComplete:` sibling of `main:` at same indent (4 spaces). Use bare `success` shorthand, NOT `workflow.success`. **Nextflow 26.04.0 parser bug:** list literals in `main:` body cause "Unexpected input: ':'" when `onComplete:` is a sibling. Workaround: move logic to sub-workflow, top-level handles completion.

### 6. Stub Block Placement

`stub:` must appear AFTER `script:`, never before.

### 7. Template Dollar Escaping

All bare `$` in `.r`/`.py`/`.sh` template files that aren't `${...}` Nextflow substitutions must be escaped as `\$`. Patterns: `$V1`, `$seurat`, `$cluster_summary`, `$_SVR`, `$\"` (dollar before closing quote). R `[[ ]]` syntax preferred over `$` for column access. Use `od -c` to verify byte patterns.

### 7F. Groovy Backslash Escapes in Python Templates (`\n`, `\t`, `\r`)

All single `\n`, `\t`, `\r` in Nextflow template `.py`/`.r`/`.sh` files are processed by Groovy's GStringTemplateEngine BEFORE the script runs — `\n` becomes literal newline, `\t` becomes literal tab. Use `\\n` (double backslash) or `chr(10)` / `chr(9)` to survive rendering.

**Detection:**
```bash
find modules -path '*/templates/*.py' | xargs grep -Pn '(?<!\\\\)\\\\([ntr])'
```

**Error signature:** `SyntaxError: unterminated string literal` on a `print("` line in `.command.sh`.

### 7B. Template Escaping Verification (Byte-Level)

Clear Nextflow work dir when testing template fixes. Use `od -c` to verify actual file bytes — `cat`/editor display may visually normalize `\$`.

### 7C. Beware: read_file()/write_file() Round-Trip Corruption

`read_file()` returns line-number-prefixed content — writing it back corrupts the file. Use heredocs, `python3 -c`, `sed`, or `skill_manage action=patch` for template edits.

### 7D. Process Memory Oversubscription on Local Hardware

Base.config may set memory too high for local workstation (e.g. 32 GB requested vs 31.2 GB available). Override in `local-gpu.config` with lower profile-scoped `withName` block.

### 7E. file.copy(, overwrite=TRUE) Fails When Staged File and Output Share Same Name

Read the staged file directly instead of copy-then-read. Staged file is already in the work dir.

### 8. Every Process Must Have a Stub Block

Required for `-stub-run` CI smoke tests. Creates empty/touched output files matching expected output structure.

### 9. Config Files: No Top-Level `def` (Nextflow 26.04+)

`def` declarations at top level of `.config` files cannot coexist with config blocks. Inline the expression where used.

## Common Error Messages and Root Causes

| Error | Root Pattern | Fix |
|---|---|---|
| `token recognition error at '\\'` | `$"` (bare dollar before closing quote) | `\$"` |
| `No such property 'V1'` | `$V1` | `\$V1` |
| `No such property 'seurat'` | `$seurat` in `obj$seurat` | `obj\$seurat` or `obj[["seurat"]]` |
| `Access to undefined parameter` | `"${params.x}"` in container directive | `{ params.x }` |
| `SyntaxError: unterminated string literal` | `\n`/`\t`/`\r` single backslash in `.py` template | `\\n` or `chr(10)`/`chr(9)` |
| `DataflowVariable (value=null)` | `.out` captured in `.map{}` closure | Dual-emit or `.combine()` |
| `Process requirement exceeds available memory` | `withName` memory > available RAM | Override in profile config |

## Logical Flow Checks

- **Module chaining:** take/emit match downstream/upstream
- **Parameter consistency:** workflow->process params match declared inputs
- **Channel transforms:** `.map`, `.collect`, `.split`, `.branch` produce expected types
- **File-mode inputs:** processes expecting `tuple val(meta), path(file)` must get `.map { meta -> [meta, file(meta.field)] }` wrapping
- **Channel builder checklist:** `id`, `species`, `mode`, `output_file_id`/`url`/`path`/`metadata_path`, `SubjectId`, `epitope_file`

## Profile-Aware Resource Validation

Every process label must have `withLabel` entry in ALL profile configs: `slurm.config`, `local-gpu.config`, `test.config`. Cross-check with:
```bash
for label in $(grep -rh "label '" modules/ --include='main.nf' | sort -u); do
  echo "=== $label ==="
  for cfg in configs/slurm.config configs/local-gpu.config configs/test.config; do
    found=$(grep -c "withLabel: '$label'" "$cfg" 2>/dev/null || echo 0)
    echo "  $cfg: $found"
  done
done
```

## Shell Script Traps

- `set -euo pipefail` + `grep`: append `|| true` to grep commands in pipelines
- `.netrc` volume mount only on `process_ingest_labkey` — NOT on tabulate/ingest_file/ingest_url/export

## Debugging Nextflow Error Cascades

The visible error is often secondary. Find the first exception by reading upward from the bottom of `nextflow.log`. Look for:
```
error [nextflow.exception.ProcessUnrecoverableException]: Input tuple does not match tuple declaration
```
