# TODOs — Audit Findings & Follow-ups

> Auto-generated 2026-05-01 from exhaustive repo audit (git history + all source + all memory-bank files).

---

## 🔴 Bugs / Functional Gaps

### 1. INGEST_METADATA has NO label-specific config in any profile
- **What:** `INGEST_METADATA` module uses label `process_ingest`, but NO config profile defines `withLabel: 'process_ingest'`. All profiles define `process_ingest_labkey`, `process_ingest_url`, `process_ingest_file` — never the plain `process_ingest`.
- **Impact:** INGEST_METADATA falls through to global defaults in all profiles. It gets NO `.netrc` volume mount, yet it downloads metadata from LabKey via `DownloadMetadataForSeuratObject()` which requires LabKey authentication.
- **Files affected:** `modules/local/rdiscvr/ingest_metadata/main.nf` (uses `process_ingest`), all config profiles (`local.config`, `local-gpu.config`, `slurm.config`, `slurm_singularity.config`)
- **Fix:** Either (a) add `withLabel: 'process_ingest'` blocks to config profiles with `.netrc` mount + resource specs, OR (b) change INGEST_METADATA's label to `process_ingest_labkey` to piggyback on existing LabKey config.

### 2. Memory bank `configs.md` has wrong label table
- **What:** Lists `process_ingest` as a unified label across all profiles (lines 69, 103, 144), but actual configs use 3 separate labels: `process_ingest_labkey`, `process_ingest_url`, `process_ingest_file`.
- **Impact:** Misleading for anyone reading the memory bank to understand resource allocation. The tri-mode refactor split the labels but the configs memory doc wasn't updated.
- **Fix:** Rewrite the per-label tables in `configs.md` to reflect the actual 3+ distinct ingest labels.

### 3. `local-gpu.config` missing from conventions.md config inheritance diagram
- **What:** `memory-bank/conventions.md` line 22 shows config inheritance tree without `local-gpu.config`. `configs.md` line 12 also omits it.
- **Impact:** Incomplete architectural documentation.
- **Fix:** Add `local-gpu.config` to both diagrams.

---

## 🟡 Follow-ups (from previous session)

### 4. MCP server doesn't know about `ingest_file`
- **What:** Session notes (2026-04-30) listed this as pending. `search_files` in `mcp-server/src/` confirms 0 references to `ingest_file`.
- **Impact:** `suggest-pipeline` and `compose-workflow` MCP tools won't include `ingest_file` in suggestions.
- **Fix:** Update `mcp-server/src/composition/suggest-pipeline.ts` and `compose-workflow.ts` to add `ingest_file` to the module catalog.

### 5. Old dead `tests/modules/ingest.nf` cleanup
- Session notes mention old `tests/modules/ingest.nf` as dead code. The file is now gone (confirmed via listing — only `ingest_labkey.nf`, `ingest_url.nf`, `ingest_file.nf` exist). The old `modules/local/rdiscvr/ingest/` directory is also gone. 
- **Status:** ✅ Already resolved.

---

## 🟢 Minor / Cosmetic

### 6. `nextflow_synatx.md` filename typo
- **What:** The file is named `nextflow_synatx.md` (misplaced 'a' in 'syntax').
- **Impact:** Cosmetic. All internal references use this spelling consistently, so no broken links.
- **Fix:** Rename if desired, update references in `conventions.md` and `session-notes.md`.

### 7. `process_harmonize` missing maxRetries in local profiles
- **What:** `process_harmonize` has no `errorStrategy`/`maxRetries` in `local.config` or `local-gpu.config`. If GENE_HARMONIZE OOMs, it fails immediately with no retry.
- **Impact:** Minor — harmonization runs on CPU with modest memory needs, but could be a gap for very large datasets.
- **Fix:** Optionally add retry logic.

---

## ✅ Verified Correct (no action needed)

- All 8 modules have `stub:` blocks ✅
- All `tag`/`publishDir` directives use static strings (DSL2 26.04 compliant) ✅
- Workflows use `if/else` chains, not `switch` (DSL2 compliant) ✅
- `$` in R heredocs escaped as `\$` ✅
- `base.config` → profile config layering correct, no param duplication ✅
- Tri-mode ingest (LABKEY/URL/FILE) fully deployed across all 3 workflows ✅
- `local-gpu.config` GPU retry on exit 42/137 with batch_size reduction ✅
- `slurm.config` `process_gpu` also has exit 42/137 retry ✅
- `slurm_singularity.config` has Apptainer before/after scripts ✅
- `test.config` disables all container engines for stub runs ✅
- All CI module tests present for current modules ✅
- `nextflow.config` profiles: `standard`, `auto`, `slurm`, `slurm_singularity`, `local`, `local_gpu`, `test` all wired ✅