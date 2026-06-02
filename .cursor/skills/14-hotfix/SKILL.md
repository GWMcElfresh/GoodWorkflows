---
name: 14-hotfix
description: Fix GoodWorkflows bugs from CI, Nextflow logs, generated .command.sh files, template runtime errors, or failed smoke/real runs.
---

# 14 Hotfix

Start with evidence, not guesses.

## Debug Path

1. For GitHub Actions PR failures, load `debug-github-actions-pr` first (resolve PR, pull failed logs, extract errors with context) before guessing.
2. Identify the first root cause in `nextflow.log`, CI output, or generated `.command.sh`.
3. Classify the surface: DSL2, config, template runtime, launcher, docs/schema, CI, or data fixture.
4. Load the matching domain skill.
5. Make the smallest fix that addresses the root cause.
6. Add or update a targeted regression check where practical.
7. Run focused verification.

## Common GoodWorkflows Hotfix Areas

- Groovy template `$` or escape rendering.
- Missing `stub:` outputs.
- Channel tuple mismatch.
- Config-level `def` or container closure warnings.
- Stale generated example data or samplesheets.

## Output

Record root cause, fix surface, verification, and any follow-up drift in state.
