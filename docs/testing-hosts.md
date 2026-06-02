# Testing on multiple hosts

GoodWorkflows local testing branches by machine capability. CI remains stub-only on GitHub Actions; this page covers developer machines.

## Quick start

From the repository root:

```bash
bash scripts/test/run_host_tests.sh
bash scripts/test/run_host_tests.sh --affected
bash scripts/test/run_host_tests.sh --host mac --tier real --workflow ingest_export
bash scripts/test/run_host_tests.sh --host wsl --tier stub
```

## Host profiles

Configuration: `template/gw/test-hosts.yaml` (at the repository root; not part of the docs site)

| Host | Auto-detect | Default tier | Real runs |
|------|-------------|--------------|-----------|
| **wsl** | `$WSL_DISTRO_NAME` or Microsoft in `/proc/version` | light | Not allowed |
| **mac** | `uname` Darwin | stub | CPU workflows via `-profile local` |
| **bazzite** | Linux + Podman + NVIDIA GPU | stub | All workflows via `-profile local_gpu` |

Override with gitignored `template/gw/.test-host`:

```bash
export GW_TEST_HOST=bazzite
```

## Tiers

| Tier | What runs |
|------|-----------|
| **light** | `nextflow config`, `bash -n` / ShellCheck, CI smoke for affected or default workflow |
| **stub** | Serial `-stub-run` for all workflows via `template/gw/check_workflows.sh` |
| **real** | Podman container runs; host-filtered (Mac skips GPU workflows with `SKIP`) |

## CPU vs GPU workflows

| CPU (real on Mac) | GPU (stub on Mac real tier; full real on Bazzite) |
|-------------------|---------------------------------------------------|
| `ingest_export` | `integration` |
| `ingest_tabulate` | `nmf_vae` |
| `batch_effect_assessments` | `gex_mil`, `tcr_mil`, `tcr_epitope`, `make_tcr_vector_database` |

## Cursor integration

- **Skill:** `18-host-test` — invoke with “run host tests” or “Use 18-host-test”
- **Hook:** `verification_hint.py` suggests `bash scripts/test/run_host_tests.sh --affected` after relevant edits

## Prerequisites by tier

| Tier | WSL | Mac | Bazzite |
|------|-----|-----|---------|
| light | Nextflow optional | Nextflow optional | Nextflow optional |
| stub | Nextflow | Nextflow | Nextflow |
| real | — | Podman, `fetch_example_data.sh` | Podman, GPU, `setup.sh`, test data |

Stub-run validates DSL2 wiring only. Real tier exercises containers and compute on the host.
