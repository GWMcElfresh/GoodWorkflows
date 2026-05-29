---
name: debug-github-actions-pr
description: >-
  Investigates failing GitHub Actions on a pull request using gh: resolves the PR,
  lists failed checks, downloads failed-job logs only, extracts ERROR/error/Error lines
  with context, and summarizes root cause with local repro hints. Use when the user
  asks to debug CI, fix a red PR check, investigate GitHub Actions failures, or
  triage gh run logs.
disable-model-invocation: true
---

# Debug GitHub Actions PR

Token-efficient CI triage for GoodWorkflows PRs. Complements the built-in `ci-investigator` subagent; follow this runbook when investigating red checks.

## Prerequisites

```bash
gh auth status
gh repo view --json nameWithOwner -q .nameWithOwner
```

Request `full_network` or `all` if sandbox blocks `gh`. Do not use `gh run view --log` unless `--log-failed` returns nothing useful.

## 1. Resolve the PR

Precedence: PR URL or number → explicit branch → current branch.

```bash
# By number
gh pr view <N> --json number,url,headRefName,baseRefName,statusCheckRollup

# Current branch
gh pr list --head "$(git branch --show-current)" --json number,url,headRefName,baseRefName --limit 1
```

If no PR exists for the branch, stop and report. Do not invent a workflow run.

## 2. List failing checks only

```bash
gh pr checks <N>
gh pr checks <N> --json name,state,link,workflowRun \
  --jq '[.[] | select(.state == "FAILURE" or .state == "FAILED")]'
```

If checks are empty but the PR is not mergeable, list failed runs on the head branch:

```bash
gh run list --branch <headRefName> --limit 10 \
  --json databaseId,workflowName,conclusion,displayTitle,url \
  --jq '[.[] | select(.conclusion == "failure")]'
```

Record each failed check name and its `workflowRun` URL or run ID when present.

## 3. Pull failed logs (one run at a time)

Default (failed jobs only):

```bash
gh run view <run-id> --log-failed 2>&1 | tee /tmp/gw-ci-failed.log
```

Matrix job or incomplete `--log-failed`:

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
gh api "repos/${REPO}/actions/runs/<run-id>/jobs" \
  --jq '.jobs[] | select(.conclusion == "failure") | {id, name}'
gh run view <run-id> --job <job-id> --log 2>&1 | tee /tmp/gw-ci-job.log
```

Record the matrix cell from the job name (e.g. `workflow (integration)`).

**Helper script** (preferred for bounded excerpts):

```bash
bash .cursor/skills/debug-github-actions-pr/scripts/extract_run_errors.sh <run-id> [job-id]
```

## 4. Extract error lines with context

Manual extraction when not using the script:

```bash
LOG=/tmp/gw-ci-failed.log   # or /tmp/gw-ci-job.log
rg -i '(::error::|##\[error\]|WARNING -\s|Aborted with|\bERROR\b|\bError\b|\berror\b|FAILED|Traceback|AssertionError|Script_|ERROR ~|strict mode)' \
  -C 10 --max-count 25 "$LOG"
```

**Analysis rules**

- Walk matches top to bottom; the **first** non-recurring signal is usually root cause.
- Ignore duplicate matrix retries and post-failure cleanup unless they add new information.
- `::error::` alone: read lines above (ShellCheck SC####, missing file).
- MkDocs strict: `WARNING -` then `Aborted with N warnings in strict mode` (fix the first WARNING, not only exit code 1).
- Nextflow: look for `ERROR ~`, `Script_`, channel/tuple errors, missing `stub:` outputs.
- MCP: `Check test results` may fail after `continue-on-error`; read the failing pytest step output above the aggregation step.

Map failures to local repro using [reference.md](reference.md). Load `goodworkflows-verify` and `14-hotfix` for fixes.

## 5. Classify

Answer from log context:

| Question | Source |
|----------|--------|
| What failed? | Step name, matrix cell, workflow file (`.github/workflows/*.yml`) |
| Why? | First actionable error message |
| Fix surface | DSL2, config, template, shell, docs, MCP, CI script |
| Unrelated to PR? | Branch behind `main`; another PR may have fixed `main` — suggest rebase before code changes |

## 6. Report template

```markdown
## CI failure summary — PR #N

**PR:** <url> | **Head:** <branch> | **Failed checks:** <names>

### Primary failure
- **Workflow/run:** <name> (<url>)
- **Job/matrix cell:** <if any>
- **First error (excerpt):**
  ```text
  <5–20 lines including context>
  ```

### Root cause
<1–3 sentences>

### Suggested local repro
<command from reference.md or goodworkflows-verify>

### Fix surface
<DSL2 | config | template | shell | docs | MCP | CI script>

### Next step
<smallest fix or rebase onto main if unrelated>
```

Do not claim the fix is verified until local repro passes or CI is green again.

## After triage

- Apply fixes via `14-hotfix` with the matching domain skill.
- Re-run the suggested local repro before pushing.
- Re-check with `gh pr checks <N>` after push.

## Additional resources

- GoodWorkflows job → repro table: [reference.md](reference.md)
- CI overview: `memory-bank/ci-cd.md`
- Local verification matrix: `goodworkflows-verify`
