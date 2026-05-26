# Requirements grill: make_tcr_vector_database

| Field | Value |
| --- | --- |
| Evolve cycle | `EV-001` |
| CLI value | `make_tcr_vector_database` |
| Status | `accepted` |
| Created | 2026-05-26 |
| Accepted | _(empty until sign-off)_ |

## User brief (from kickoff)

- **CLI value:** `make_tcr_vector_database`
- **Scientific goal:** Using ESM-2, read alpha and beta sequences from a Seurat object's TRA and TRB columns and create a vector database to determine similarity in protein sequences.
- **Scope:** Ingest Seurat objects (files or LabKey), pull ESM-2 with caching, embed vectors. Outputs as parquet. Fault-tolerant TRA/TRB handling (comma-concatenated TRA, missing TRA or TRB).
- **Inputs and samplesheet expectations:** Seurat objects with sanitized (no commas) TRA/TRB columns. Output parquets linked by `cDNA_ID` filenames. Tables track `SubjectId`, `cDNA_ID`, sequence, and embedding.
- **Tools:** Rdiscvr docker for clones via `cDNA_ID` ([TCR.R](https://github.com/bimberlabinternal/Rdiscvr/blob/21d5100c666482db6d8f27d58ee29276edd565e0/R/TCR.R#L13-L75)); [MIL-ton](https://github.com/GWMcElfresh/MIL-ton) docker for transformers (packages may need MIL-ton image work).
- **Compute target:** &lt;24 hours per batch with strong resume; fungible on wall time if resume is solid.
- **Required outputs:** Parquet files with TCR embeddings and `cDNA_ID` tracking.
- **Known constraints:** Pull ESM-2 fresh on GitHub runners (size); smaller models for test/verification; larger models on HPC profiles.
- **Verification target:** yes. Run stub-run + local heavier tests on templates/gw (lightweight smoke first, heavier locally), and ensure schema-level checks are easy in templates/gw.

---

## Recorded answers

| # | Topic | Status | Answer |
| --- | --- | --- | --- |
| 1–4 | Workflow identity | open | |
| 5–9 | Samplesheet | open | |
| 10–15 | TRA/TRB semantics | open | |
| 16–21 | Outputs | open | |
| 22–26 | ESM-2 / params | open | |
| 27–31 | Compute / resume | open | |
| 32–34 | Containers | open | |
| 35–38 | Verification / docs | **blocking** | |
| Quick | Decision table | open | |

---

## 1. Workflow identity

### 1.1 Relationship to existing workflows

**Q1.** Is this workflow distinct from `tcr_epitope` (no `QUANTIFY_TCR` / tcrClustR / epitope stages—only ingest + TRA/TRB extraction + ESM-2 + parquet)?

**Answer:** This is distinct. We don't need to count the cells in this workflow, just embed them.

**Q2.** Reuse existing modules (`INGEST_*`, embed patterns) vs new namespace (e.g. `tcr_vector_db/`)?

**Answer:** reuse whenever possible

**Q3.** When is Rdiscvr `DownloadAndAppendTcrClonotypes` required (missing TRA/TRB, always on LabKey, never if RDS is pre-populated)?

**Answer:** DownloadAndAppendTcrClonotypes is always available/required for these datasets. 

**Q4.** If Rdiscvr runs, match production defaults for `allowMissing` / per-`BarcodePrefix` skip?

**Answer:** Yes, fail gracefully

---

## 2. Samplesheet contract (drift ledger)

**Q5.** Same tri-mode ingest (`output_file_id` \| `url` \| `path`) as other workflows, or workflow-specific columns?

**Answer:** same tri-mode ingest

**Q6.** `sample_id` vs `cDNA_ID`: always equal on samplesheet, or read `cDNA_ID` from Seurat with `sample_id` only for routing?

**Answer:** we'll have to read the cDNA_ID from the seurat object. 

**Q7.** Required vs optional extra samplesheet columns (e.g. `SubjectId`, `disease_status`)?

**Answer:** We'll need to do joins on tables later, so only cDNA_ID and subject ID

**Q8.** `SubjectId` source of truth: samplesheet, Seurat, or both with precedence rule?

**Answer:** These should not conflict. 

**Q9.** Mixed ingest modes in one run—in scope for v1?

**Answer:** Mixed ingest modes are fine to support - they should infer from the string/columns and run in parallle.

### Samplesheet drift surfaces (check when accepted)

- [x] Workflow parser in `workflows/*.nf`
- [x] Samplesheet validator (if any)
- [x] Example samplesheet under `test-data/`
- [x] `docs/data-formats.md`
- [x] `nextflow_schema.json`
- [x] Launcher / generator (`template/gw`, `template/cluster`)
- [x] CI smoke samplesheet
- [x] `memory-bank/` references

---

## 3. TRA/TRB semantics

**Q10.** Comma-separated TRA: split into multiple sequences, reject, or require upstream sanitization?

**Answer:** split into multiple sequences, but this also applies to TRB

**Q11.** Missing chain (TRA only or TRB only): embed present chain only, placeholder sequence, or skip cell?

**Answer:** embed present chain only

**Q12.** Multiple sequences per chain: separate rows per `(barcode, chain, sequence_index)`?

**Answer:** yes

**Q13.** Column names: strict `TRA`/`TRB` or aliases (`TRA_CDR3`, etc.)?

**Answer:** strict TRA/TRB

**Q14.** Apply Rdiscvr-style conflicting V/J dropping before embed?

**Answer:** Yes

**Q15.** Deduplication: per cell×sequence vs unique AA string; stable `sequence_id` if deduping?

**Answer:** We'll track clones, so identical sequences from different subjectIds get different indexes, but pooling sequence indices across cDNA_Ids (but within the same non-NA/missing subjectId is fine)

---

## 4. Outputs and vector database

**Q16.** Deliverable: parquet only vs in-workflow ANN index (FAISS, hnswlib, etc.)?

**Answer:** in-workflow ANN index (FAISS, hnswlib, etc.) whichever is best supported and easiest to use at scale.

**Q17.** Output filename pattern (`{cDNA_ID}.parquet`, per chain, per barcode, other)?

**Answer:** {cDNA_ID}.parquet all chains should be in the single parquet.

**Q18.** One parquet per cDNA_ID vs per ingest unit vs sharded batches?

**Answer:** one parquet per cDNA_ID. They are small and serve as natural shards. However, we should split them into single chain and paired chain (see question 20)

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

**Answer:** this is good

**Q20.** Dual-chain: per-chain embeddings only, or also concatenated TRA+TRB vector?

**Answer:** Include a second file, such that each cDNA_ID has the paired version (clones with both alpha and beta) and then one that has a single-chain version, but put both alpha and beta in that table.

**Q21.** Published directory under `params.outdir` (e.g. `outputs/make_tcr_vector_database/`)?

**Answer:** tcr_vectordbs

---

## 5. Params, ESM-2, caching

**Q22.** HPC production model id and profile mapping (`test` / `local-gpu` / `slurm`)?

**Answer:** esm2_t48_15B_UR50D() should be used on slurm/slurm-singularity and esm2_t6_8M_UR50D should be used locally.

**Q23.** `tcr_embedding_dim` param fixed vs inferred from model?

**Answer:** inferred

**Q24.** HuggingFace cache location / shared cluster cache policy?

**Answer:** cache to the root directory in GoodWorkflows, since I'll kick off jobs from runs/

**Q25.** CI/smoke: small model only; no large-model download in GitHub runners?

**Answer:** smoke tests can avoid the model, but for the local test we should pull the small model

**Q26.** ESM `batch_size` default and max for SLA?

**Answer:** Depends, I cannot yet predict how many equences can fit on a GPU with the model. give it a best estimate. 

---

## 6. Compute, resume, batching

**Q27.** Definition of “batch” for &lt;24h SLA (samplesheet row, cDNA_ID, SLURM job, full run)?

**Answer:** batch = how many cells to load onto the GPU at one time.

**Q28.** Resume: Nextflow `-resume` only vs within-process checkpoints?

**Answer:** good question - ideally I want this to pick up where it left off if the job is killed due to time and I re-submit via sbatch run.sh

**Q29.** Parallelism model (per sample GPU task vs global queue vs cell chunks)?

**Answer:** should be unnecessary - we should run 1 job per cDNA_ID and all of the cells + model should fit on a A40

**Q30.** Process labels and resources (`process_gpu`, CPU fallback, VRAM for large model)?

**Answer:** yes, but we should be fine on the gpus. for local testing we will need to use cpus

**Q31.** Runs over 24h acceptable if resume is reliable?

**Answer:** ideally we have a 'pick up where I left off' resume behavior when I resubmit jobs and keep the job at a 24 hour time limit.

---

## 7. Container split (Rdiscvr vs MIL-ton)

**Q32.** Stage order (ingest → optional Rdiscvr TCR append → extract → embed → publish)?

**Answer:** yes, but once we have the embeddings we should also append them to the seurat object and give those back to the metadata. 

**Q33.** MIL-ton container scope: ESM-2 + parquet only; Seurat I/O in Rdiscvr?

**Answer:** yes

**Q34.** MIL-ton image deps tracked in MIL-ton repo before GoodWorkflows wiring?

**Answer:** yes

---

## 8. Docs, schema, verification

**Q35.** Minimum verification sign-off (stub-run, local GPU on SMOKE.rds, SLURM smoke, schema tests)?

**Answer:** yes. I will have to run heavier tests on my local machine. Ensure this is easy for me in the templates/gw directory

**Q36.** Acceptance criteria (row counts, missing-chain behavior, resume semantics)?

**Answer:** covered above

**Q37.** Update workflow count and registry surfaces (eighth workflow)?

**Answer:** yes

**Q38.** New `docs/workflows/<name>.md` stage table required?

**Answer:** yes

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
| Requester | GW | 5/26 | |
| Agent / implementer | | | Requirements accepted for `02-verify-plan` |

**Open blockers:** none (verification target + acceptance criteria captured in Q35/Q36 answers above).
