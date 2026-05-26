# Requirements grill: {CLI_VALUE}

| Field | Value |
| --- | --- |
| Evolve cycle | `{CYCLE_ID}` |
| CLI value | `{CLI_VALUE}` |
| Status | `open` \| `in_review` \| `accepted` |
| Created | `{ISO_DATE}` |
| Accepted | _(empty until sign-off)_ |

## User brief (from kickoff)

_Paste the workflow kickoff bullets here._

- CLI value:
- Scientific goal:
- Scope:
- Inputs and samplesheet expectations:
- Tools, modules, templates, or containers:
- Compute target:
- Required outputs:
- Known constraints:
- Verification target:

---

## Recorded answers

_Agents and humans fill **Answer** blocks. Leave `_(pending)_` until decided. Mark blocking items in **Status** column._

| # | Topic | Status | Answer |
| --- | --- | --- | --- |
| _(populate from sections below)_ | | | |

---

## 1. Workflow identity

### 1.1 Relationship to existing workflows

**Q1.** Is this workflow distinct from `tcr_epitope` (no `QUANTIFY_TCR` / tcrClustR / epitope stages—only ingest + TRA/TRB extraction + ESM-2 + parquet)?

**Answer:** _(pending)_

**Q2.** Reuse existing modules (`INGEST_*`, embed patterns) vs new namespace (e.g. `tcr_vector_db/`)?

**Answer:** _(pending)_

**Q3.** When is Rdiscvr `DownloadAndAppendTcrClonotypes` required (missing TRA/TRB, always on LabKey, never if RDS is pre-populated)?

**Answer:** _(pending)_

**Q4.** If Rdiscvr runs, match production defaults for `allowMissing` / per-`BarcodePrefix` skip?

**Answer:** _(pending)_

---

## 2. Samplesheet contract (drift ledger)

**Q5.** Same tri-mode ingest (`output_file_id` \| `url` \| `path`) as other workflows, or workflow-specific columns?

**Answer:** _(pending)_

**Q6.** `sample_id` vs `cDNA_ID`: always equal on samplesheet, or read `cDNA_ID` from Seurat with `sample_id` only for routing?

**Answer:** _(pending)_

**Q7.** Required vs optional extra samplesheet columns (e.g. `SubjectId`, `disease_status`)?

**Answer:** _(pending)_

**Q8.** `SubjectId` source of truth: samplesheet, Seurat, or both with precedence rule?

**Answer:** _(pending)_

**Q9.** Mixed ingest modes in one run—in scope for v1?

**Answer:** _(pending)_

### Samplesheet drift surfaces (check when accepted)

- [ ] Workflow parser in `workflows/*.nf`
- [ ] Samplesheet validator (if any)
- [ ] Example samplesheet under `test-data/`
- [ ] `docs/data-formats.md`
- [ ] `nextflow_schema.json`
- [ ] Launcher / generator (`template/gw`, `template/cluster`)
- [ ] CI smoke samplesheet
- [ ] `memory-bank/` references

---

## 3. TRA/TRB semantics

**Q10.** Comma-separated TRA: split into multiple sequences, reject, or require upstream sanitization?

**Answer:** _(pending)_

**Q11.** Missing chain (TRA only or TRB only): embed present chain only, placeholder sequence, or skip cell?

**Answer:** _(pending)_

**Q12.** Multiple sequences per chain: separate rows per `(barcode, chain, sequence_index)`?

**Answer:** _(pending)_

**Q13.** Column names: strict `TRA`/`TRB` or aliases (`TRA_CDR3`, etc.)?

**Answer:** _(pending)_

**Q14.** Apply Rdiscvr-style conflicting V/J dropping before embed?

**Answer:** _(pending)_

**Q15.** Deduplication: per cell×sequence vs unique AA string; stable `sequence_id` if deduping?

**Answer:** _(pending)_

---

## 4. Outputs and vector database

**Q16.** Deliverable: parquet only vs in-workflow ANN index (FAISS, hnswlib, etc.)?

**Answer:** _(pending)_

**Q17.** Output filename pattern (`{cDNA_ID}.parquet`, per chain, per barcode, other)?

**Answer:** _(pending)_

**Q18.** One parquet per cDNA_ID vs per ingest unit vs sharded batches?

**Answer:** _(pending)_

**Q19.** Confirm parquet schema (columns, embedding storage shape):

| Column | Required? | Notes |
| --- | --- | --- |
| `cDNA_ID` | | |
| `SubjectId` | | |
| `barcode` | | |
| `chain` | | |
| `sequence` | | |
| `embedding` | | array vs wide columns |
| `sequence_index` | | |
| `esm2_model` | | |
| `sample_id` | | |

**Answer:** _(pending)_

**Q20.** Dual-chain: per-chain embeddings only, or also concatenated TRA+TRB vector?

**Answer:** _(pending)_

**Q21.** Published directory under `params.outdir` (e.g. `outputs/make_tcr_vector_database/`)?

**Answer:** _(pending)_

---

## 5. Params, ESM-2, caching

**Q22.** HPC production model id and profile mapping (`test` / `local-gpu` / `slurm`)?

**Answer:** _(pending)_

**Q23.** `tcr_embedding_dim` param fixed vs inferred from model?

**Answer:** _(pending)_

**Q24.** HuggingFace cache location / shared cluster cache policy?

**Answer:** _(pending)_

**Q25.** CI/smoke: small model only; no large-model download in GitHub runners?

**Answer:** _(pending)_

**Q26.** ESM `batch_size` default and max for SLA?

**Answer:** _(pending)_

---

## 6. Compute, resume, batching

**Q27.** Definition of “batch” for &lt;24h SLA (samplesheet row, cDNA_ID, SLURM job, full run)?

**Answer:** _(pending)_

**Q28.** Resume: Nextflow `-resume` only vs within-process checkpoints?

**Answer:** _(pending)_

**Q29.** Parallelism model (per sample GPU task vs global queue vs cell chunks)?

**Answer:** _(pending)_

**Q30.** Process labels and resources (`process_gpu`, CPU fallback, VRAM for large model)?

**Answer:** _(pending)_

**Q31.** Runs over 24h acceptable if resume is reliable?

**Answer:** _(pending)_

---

## 7. Container split (Rdiscvr vs MIL-ton)

**Q32.** Stage order (ingest → optional Rdiscvr TCR append → extract → embed → publish)?

**Answer:** _(pending)_

**Q33.** MIL-ton container scope: ESM-2 + parquet only; Seurat I/O in Rdiscvr?

**Answer:** _(pending)_

**Q34.** MIL-ton image deps tracked in MIL-ton repo before GoodWorkflows wiring?

**Answer:** _(pending)_

---

## 8. Docs, schema, verification

**Q35.** Minimum verification sign-off (stub-run, local GPU on SMOKE.rds, SLURM smoke, schema tests)?

**Answer:** _(pending)_ **(blocking)**

**Q36.** Acceptance criteria (row counts, missing-chain behavior, resume semantics)?

**Answer:** _(pending)_ **(blocking)**

**Q37.** Update workflow count and registry surfaces (eighth workflow)?

**Answer:** _(pending)_

**Q38.** New `docs/workflows/<name>.md` stage table required?

**Answer:** _(pending)_

---

## 9. Quick decisions (optional)

| Topic | Choice (A / B / C) | Notes |
| --- | --- | --- |
| tcrClustR | A skip / B optional / C required | |
| Comma TRA | A split / B fail / C pre-sanitize | |
| Missing TRB | A TRA only / B placeholder / C skip cell | |
| Output key | A cDNA_ID / B sample_id / C per barcode | |
| Vector DB | A parquet only / B + index / C v2 | |
| SubjectId | A sheet / B Seurat / C sheet wins | |

---

## Sign-off

| Role | Name | Date | Notes |
| --- | --- | --- | --- |
| Requester | | | |
| Agent / implementer | | | Requirements accepted for `02-verify-plan` |

**Open blockers:** _(list any `#` still pending)_
