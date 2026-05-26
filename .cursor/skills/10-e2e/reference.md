# GoodWorkflows E2E and `check_workflows.sh` Reference

Migrated from the retired root `skills/` directory.

## `template/gw/check_workflows.sh`

The local serial workflow runner should:

- discover supported workflows from `main.nf` where possible.
- provide registry entries only for non-default samplesheets or extra flags.
- create timestamped run directories under `template/gw/runs/`.
- maintain a `runs/latest` pointer when supported.
- run stub mode by default and real mode only when explicitly requested.

## Stub vs Real

- Stub mode validates DSL2 wiring and `stub:` outputs without real containers.
- Real mode uses local runner scripts and toy/generated data; it can fail for container, data, GPU, or runtime reasons outside DSL2 wiring.

## Stale Test Data

If `ingest_tabulate` fails with no cell-type columns, generated metadata CSVs may be stale or overwritten by stub outputs. Regenerate example data from `template/gw/fetch_example_data.sh` before treating it as a workflow logic bug.

## TCR Test Data

TCR workflows need synthetic TRA/TRB CDR3 sequences and V/J metadata in generated fixtures. If using synthetic V/J genes that external tools validate against a database, set V/J values to `NA` when the goal is smoke testing rather than biological validation.
