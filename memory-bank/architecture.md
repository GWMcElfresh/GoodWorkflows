# Architecture

## DSL2 Module Graph

```
┌────────────────┐     ┌───────────────┐     ┌────────────────┐     ┌───────────────────┐
│ INGEST_LABKEY  │────▶│               │     │                │     │                   │
│ INGEST_URL     │────▶│ EXPORT_COUNTS │────▶│ GENE_HARMONIZE │────▶│ SCMODAL_INTEGRATE │
│ INGEST_FILE    │────▶│               │     │                │     │                   │
└────────────────┘     └───────────────┘     └────────────────┘     └───────────────────┘
  rdiscvr/                cellmembrane/       gene_harmonize/         scModal/gpu/
  ingest_labkey,          seurat/
  ingest_url,
  ingest_file
```

## Entry Point: `main.nf`

A thin launcher that:
1. Includes all three workflow definitions
2. Validates `--workflow` against `['integration', 'ingest_export', 'ingest_tabulate']`
3. Validates required params (`--labkey_base_url`, `--labkey_folder`, `--input`)
4. Dispatches to the selected workflow via a `switch` block
5. Reports completion/error via `workflow.onComplete` and `workflow.onError`

## Workflow Composition

### Tri-Mode Ingest Dispatch

All three workflows use the same samplesheet parser pattern. Each row must have exactly one of `output_file_id` (LabKey), `url` (HTTP download), or `path` (local file) non-empty. The parser sets `meta.mode` to `'labkey'`, `'url'`, or `'file'` accordingly, and the workflow body branches + mixes:

```groovy
ch_labkey = ch_samples.branch { meta ->
    labkey: meta.mode == 'labkey'
    url:    meta.mode == 'url'
    file:   meta.mode == 'file'
}
ch_ingested_rds = INGEST_LABKEY(ch_labkey.labkey).rds
    .mix(INGEST_URL(ch_labkey.url).rds)
    .mix(INGEST_FILE(ch_labkey.file).rds)
```

### `INTEGRATION_PIPELINE` (workflows/integration_pipeline.nf)
- **Guard:** Blocks local executor unless `--scmodal_use_cpu true` (CI-only)
- **Channel flow:**
  1. `buildIntegrationPipelineSamplesChannel(samplesheet)` → parses CSV, emits `