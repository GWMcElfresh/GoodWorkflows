---
name: 11-verify-impl
description: Verify a GoodWorkflows implementation against accepted requirements. Use after build, QA, and workflow smoke checks.
---

# 11 Verify Implementation

Compare the implemented change with the requirements and technical plan.

## Review

- Workflow CLI value and docs match.
- Samplesheet columns and params match schema/docs.
- Outputs match stubs, docs, and downstream consumers.
- Compute profile and resource assumptions are documented.
- Verification evidence supports the claims made.
- Known limitations are recorded in state or memory-bank.

## Output

Return pass/fail with remaining gaps. Update state. If gaps are code issues, route back to `07-build`; if gaps are verification issues, route to `08-verify-build` or `10-e2e`.
