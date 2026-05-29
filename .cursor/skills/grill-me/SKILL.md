---
name: grill-me
description: >-
  Run a structured requirements grill for GoodWorkflows workflow additions.
  Creates or updates requirements-grill Q&A files, records answers, and blocks
  technical planning until the contract is accepted. Use with pipeline and
  01-requirements before 02-verify-plan.
---

# Grill Me (Requirements Q&A)

Structured question-and-answer currency for workflow requirements. The grill file is the **source of record** for what was asked and decided; chat summaries are not enough for multi-session evolve cycles.

## When to Use

- Starting a new saved workflow (`pipeline` + `16-evolve`).
- Resuming `01-requirements` with open decisions.
- Any change to samplesheet columns, outputs, params, or acceptance criteria before `04-tech-plan`.

Pair with `01-requirements` and `goodworkflows-state-manager` (record grill file path in evolve cycle artifacts).

## File Convention

| Item | Rule |
| --- | --- |
| Directory | `requirements-grill/` at repo root |
| Active grill | `requirements-grill/{CYCLE_ID}-{CLI_VALUE}.md` (e.g. `EV-001-make_tcr_vector_database.md`) |
| New cycle | Copy `requirements-grill/_TEMPLATE.md`, replace placeholders, set `Status: open` |
| README | `requirements-grill/README.md` indexes active grills |

Do not store grill files under `work/`, `outputs/`, or generated run dirs.

## Workflow

### 1. Create or open the grill file

On first grill for an evolve cycle:

1. Read state (`goodworkflows-state-manager`, `read_context`) for `active_cycle` and CLI value.
2. If no file exists, copy `_TEMPLATE.md` to `{CYCLE_ID}-{CLI_VALUE}.md`.
3. Paste the user's kickoff brief into **User brief**.
4. Tailor section questions from repo context (closest workflow in `workflows/`, `docs/data-formats.md`, `memory-bank/`). Keep numbered **Q1…Qn** stable so answers can reference question ids.

### 2. Grill in chat, record in file

- Ask missing-requirements questions in chat (grouped by topic).
- After each user reply (or batch), update the matching **Answer:** blocks and the **Recorded answers** summary table.
- Set **Status** per row: `open` → `answered` → `accepted`.
- Mark **blocking** items (e.g. empty verification target) until resolved.

### 3. Acceptance gate

Do **not** proceed to `02-verify-plan` or `04-tech-plan` until:

- All **blocking** questions have non-pending answers.
- **Samplesheet drift surfaces** checklist is filled or explicitly deferred with reason.
- **Sign-off** table has requester acceptance (or user message: "requirements accepted").
- Grill file `Status` is `accepted` and state manager records the artifact path.

### 4. Handoff

Produce a short **requirements brief** (bullet contract) derived from the grill file—not from memory alone. Request state update with artifact:

`requirements-grill/{CYCLE_ID}-{CLI_VALUE}.md`

## Question Categories (minimum)

Always cover:

1. Workflow identity (overlap with existing `--workflow` values).
2. Samplesheet columns and drift ledger surfaces.
3. TRA/TRB or domain-specific input semantics.
4. Outputs, paths, and file schemas.
5. Params, models, caching, profiles.
6. Compute, resume, and batch boundaries.
7. Containers and stage order.
8. Verification target and acceptance criteria (**blocking** if missing)—must include stub-run, `check_workflows.sh --workflow <cli>`, and CI smoke when applicable.
9. Docs/schema/registry impact.
10. **Launcher surfaces** and **fixture strategy** (**blocking** for new workflows if templates promised).

Use **Quick decisions** table for A/B/C choices when the user prefers terse replies.

## Answer Format

```markdown
**Answer:** Split comma-separated TRA into multiple rows; embed TRB-missing cells with TRA only. SubjectId from Seurat; samplesheet SubjectId optional override.
```

For deferred decisions:

```markdown
**Answer:** _(deferred v2)_ — parquet-only; FAISS index out of scope for EV-001.
```

## Parent Agent Rules

- Prefer editing the grill file in the same turn as recording user answers.
- If the user edits the grill file directly, re-read it before planning.
- Subagents may **read** grill files; only the parent (or user) should mark **accepted** unless delegated explicitly.

## Related Skills

- `pipeline` — orchestrates when grilling runs (before planning).
- `01-requirements` — contract capture; must reference the grill file.
- `02-verify-plan` — verifies grill completeness and drift ledger.
- `16-evolve` — ties grill file to cycle id.

See `reference.md` for the new-workflow prompt snippet and README cross-links.
