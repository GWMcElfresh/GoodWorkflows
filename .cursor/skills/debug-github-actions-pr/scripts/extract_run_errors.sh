#!/usr/bin/env bash
# Extract bounded error excerpts from a failed GitHub Actions run.
# Usage: extract_run_errors.sh <run-id> [job-id]
set -euo pipefail

RUN_ID="${1:-}"
JOB_ID="${2:-}"

if [[ -z "$RUN_ID" ]]; then
  echo "Usage: $0 <run-id> [job-id]" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required" >&2
  exit 1
fi

# Homebrew ripgrep is common on macOS but may be missing from non-interactive PATH.
if ! command -v rg >/dev/null 2>&1 && [[ -x /opt/homebrew/bin/rg ]]; then
  PATH="/opt/homebrew/bin:${PATH}"
fi

LOG_FILE=$(mktemp "${TMPDIR:-/tmp}/gw-ci-log.XXXXXX")
trap 'rm -f "$LOG_FILE"' EXIT

if [[ -n "$JOB_ID" ]]; then
  echo "# Fetching job $JOB_ID for run $RUN_ID" >&2
  gh run view "$RUN_ID" --job "$JOB_ID" --log 2>&1 >"$LOG_FILE" || true
else
  echo "# Fetching failed logs for run $RUN_ID" >&2
  gh run view "$RUN_ID" --log-failed 2>&1 >"$LOG_FILE" || true
fi

if [[ ! -s "$LOG_FILE" ]]; then
  echo "No log output returned for run $RUN_ID" >&2
  exit 1
fi

PATTERN='(::error::|##\[error\]|WARNING -\s|Aborted with|\bERROR\b|\bError\b|\berror\b|FAILED|Traceback|AssertionError|Script_|ERROR ~|strict mode)'

if command -v rg >/dev/null 2>&1; then
  rg -i "$PATTERN" -C 10 --max-count 25 "$LOG_FILE" || {
    echo "# No error-pattern matches; last 40 lines:" >&2
    tail -40 "$LOG_FILE"
  }
else
  echo "# ripgrep not found; grep fallback" >&2
  grep -Ein '(::error::|##\[error\]|warning -|aborted with|error|failed|traceback|assertionerror|script_|error ~|strict mode)' "$LOG_FILE" | head -80 || {
    echo "# No matches; last 40 lines:" >&2
    tail -40 "$LOG_FILE"
  }
fi
