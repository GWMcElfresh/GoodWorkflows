---
name: 11-verify-impl
description: Verify a GoodWorkflows implementation against accepted requirements. Use after build, QA, and workflow smoke checks.
---

# 11 Verify Implementation

Compare the implemented change with the requirements and technical plan.

## Review

- Workflow CLI value and docs match.
- Samplesheet columns, parser/validator behavior, generated examples, launchers, tests, CI smoke inputs, params, schema/docs, and `memory-bank/` references match the accepted drift ledger.
- Outputs match stubs, docs, and downstream consumers.
- Compute profile and resource assumptions are documented.
- Verification evidence supports the claims made.
- Known limitations are recorded in state or memory-bank.

## Launcher evidence table (new workflows)

Map grill checklist items to proof:

| Grill / launcher item | Evidence |
| --- | --- |
| `template/gw/run.sh` | CLI in `VALID_WORKFLOWS`; help text |
| `check_workflows.sh` | `register` line; `check_workflows.sh --workflow <cli>` pass |
| Fixtures | Path to RDS/CSV or generator command run |
| `fetch_example_data.sh` | Section name or N/A with rationale |
| `setup.sh` / manifest | Image URI listed |
| Cluster | `docs/usage.md` + `template/cluster/run.sh` comment |
| CI | `run_nextflow_smoke_tests.sh` case; matrix row if applicable |
| Parity | `check_workflow_parity.sh` exit 0 |

**Fail** if grill launcher boxes are `[x]` without a file path or command in the evidence column.

## Effortless-run acceptance

| Target | Pass criteria |
| --- | --- |
| Local | `bash setup.sh` → data step → `bash run.sh --workflow <cli>` reaches Nextflow (stub or real per plan) |
| Cluster | Documented `WORKFLOW` + samplesheet columns + image in manifest |

## Output

Return pass/fail with remaining gaps. Update state. If gaps are code issues, route back to `07-build`; if gaps are verification issues, route to `08-verify-build` or `10-e2e`.
