# Grill Me — Reference

## New-workflow prompt (includes grill file)

```text
Use pipeline.
Start a tracked evolve cycle for a new GoodWorkflows saved workflow/pipeline.

Workflow:
- CLI value:
- Scientific goal:
- Scope:
- Inputs and samplesheet expectations:
- Tools, modules, templates, or containers to use:
- Compute target:
- Required outputs:
- Known constraints:
- Verification target:

Use grill-me: create requirements-grill/{cycle}-{cli}.md from _TEMPLATE.md,
grill me on missing requirements, and record answers in that file before planning.
Then delegate subagents by surface and proceed through the numbered skills.
```

## Editing answers offline

1. Open `requirements-grill/EV-XXX-<cli>.md`.
2. Replace `_(pending)_` under **Answer:** for each decided question.
3. Update the **Recorded answers** table Status column.
4. In chat: `Requirements updated in requirements-grill/EV-XXX-....md — continue 01-requirements.`

## Agent checklist before `02-verify-plan`

- [ ] Kickoff brief pasted in grill file
- [ ] No blocking **Answer:** still `_(pending)_`
- [ ] Samplesheet drift checklist addressed or deferred with reason
- [ ] `workflow-state.yaml` artifact lists grill file path
- [ ] Grill `Status` set to `accepted`
