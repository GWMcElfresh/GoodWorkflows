# make-tcr-vector-database

`--workflow make_tcr_vector_database`

Ingests Seurat objects, extracts TRA/TRB (alpha/beta CDR3) sequences from `meta.data`, embeds them with ESM-2, and writes per-`cDNA_ID` parquet vector databases plus a persisted nearest-neighbor index.

## Stage-by-stage dataflow

| Stage | Module | Input | Output | Compute |
|---|---|---|---|---|
| INGEST | `rdiscvr/ingest_*` | LabKey / URL / local file | `{sample_id}.rds` | CPU |
| EXTRACT_TCR_SEQUENCES | `tcr_vectordb/extract_tcr_sequences` | Seurat RDS | `${sample_id}_tcr_sequences.csv` | CPU |
| EMBED_TCR_VECTORDATABASE | `tcr_vectordb/embed_vectordb` | extracted CSV | `<cDNA_ID>_*` parquet + index | GPU |

## Samplesheet

The samplesheet must contain one row per sample with:

- `sample_id`
- exactly one of: `output_file_id` (LabKey mode), `url`, or `path`
- optional: `species` (needed only by `INGEST_FILE`)

## Output

Published under:

- `outputs/tcr_vectordbs/vectordb_out/`

For each `cDNA_ID`:

- `<cDNA_ID>_single.parquet` — rows for chain `TRA` and `TRB` with per-row embeddings
- `<cDNA_ID>_paired.parquet` — rows where both TRA and TRB sequences exist for the same `sequence_index`, with paired embeddings over `TRA:TRB`
- `<cDNA_ID>_single_index.joblib` — persisted nearest-neighbor index (sklearn, cosine distance)
- `<cDNA_ID>_paired_index.joblib` — persisted nearest-neighbor index (sklearn, cosine distance)

## Notes / constraints

- TRA/TRB may be comma-separated; the workflow splits them into multiple `sequence_index` rows.
- If TRA is present but TRB is missing (or vice-versa), the workflow embeds only the present chain for the single-chain parquet.
- If optional `TRA_V`/`TRA_J`/`TRB_V`/`TRB_J` columns are present, the workflow applies Rdiscvr-style conflicting V/J dropping before embedding.

