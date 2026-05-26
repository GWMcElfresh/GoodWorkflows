---
name: 05-verify-tech
description: Verify a GoodWorkflows technical plan before build. Use after 04-tech-plan or when checking module/workflow design consistency.
---

# 05 Verify Tech

Load `goodworkflows-dsl2-validation`, `goodworkflows-template-runtime`, and `goodworkflows-template-parity` as needed.

## Checks

- Channel contracts compose without ambiguous tuple shapes.
- Container params exist in base config and are consumed lazily in modules.
- Process labels have profile resources.
- Templates account for Groovy `$` and escape handling.
- Stub outputs match real output names and docs.
- Workflow, schema, docs, launchers, and CI updates are all listed.
- Verification commands are concrete and runnable.

## Output

Block build if critical design gaps remain. Otherwise update state and proceed to `06-tech-tooling` or `07-build`.
