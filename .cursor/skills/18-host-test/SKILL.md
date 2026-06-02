---
name: 18-host-test
description: Run GoodWorkflows host-aware local tests (WSL light, Mac CPU-real, Bazzite GPU). Use when the user asks to test locally, run smoke on this machine, verify on WSL/Mac/Bazzite, or run branched multi-host tests.
---

# 18 Host Test

Single entrypoint for local testing that respects the machine profile (WSL, macOS, Bazzite GPU workstation).

## Primary command

```bash
bash scripts/test/run_host_tests.sh [--affected] [--host auto|wsl|mac|bazzite] [--tier auto|light|stub|real] [--workflow <cli>]
```

Host profiles live in `template/gw/test-hosts.yaml`. Override auto-detection with gitignored `template/gw/.test-host`:

```bash
export GW_TEST_HOST=bazzite
```

## Routing by machine

| Host | Default tier | Real Podman | GPU real runs |
|------|--------------|-------------|---------------|
| **wsl** | `light` | No | No — use `--tier stub` for full serial stub |
| **mac** | `stub` | CPU workflows only (`-profile local`) | Stub/skip only |
| **bazzite** | `stub` | Yes | Yes (`-profile local_gpu`) |

## Tier meanings

- **light** — `nextflow config`, `bash -n` / ShellCheck on scripts, CI-equivalent smoke for affected or default workflow
- **stub** — serial `template/gw/check_workflows.sh --tier stub` (all workflows, `-stub-run`)
- **real** — serial real Podman runs via `check_workflows.sh --tier real` (host-filtered)

## When to use

- **Daily local verify after edits:** `bash scripts/test/run_host_tests.sh --affected`
- **WSL quick gate:** `bash scripts/test/run_host_tests.sh` (light default)
- **WSL full wiring check:** `bash scripts/test/run_host_tests.sh --tier stub`
- **Mac CPU real run:** `bash scripts/test/run_host_tests.sh --tier real --workflow ingest_export`
- **Bazzite GPU real:** `bash scripts/test/run_host_tests.sh --tier real --workflow integration`

## Relationship to other verification

This skill is the **local machine layer**. It does not replace the verification trio for new saved workflows:

1. `nextflow run main.nf -profile test -stub-run --workflow <cli> …`
2. `template/gw/check_workflows.sh --workflow <cli>`
3. `scripts/ci/run_nextflow_smoke_tests.sh workflow <cli>`

Real Podman/GPU/SLURM proof beyond host-filtered real tier belongs in `13-real-run-smoke` when explicitly requested.

## Execution

- Delegate command runs to **verify-runner** when available.
- Record results in **goodworkflows-state-manager** `verification_log` during numbered pipeline cycles.
- Report honestly: stub-run validates wiring, not containers/GPU/SLURM unless `--tier real` succeeded.

## Prerequisites

| Tier | WSL | Mac | Bazzite |
|------|-----|-----|---------|
| light | Nextflow optional | Nextflow optional | Nextflow optional |
| stub | Nextflow | Nextflow | Nextflow |
| real | N/A | Podman + `fetch_example_data.sh` | Podman + GPU + `setup.sh` |
