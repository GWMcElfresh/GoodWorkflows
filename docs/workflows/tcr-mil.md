# TCR MIL Pipeline

`--workflow tcr_mil`

Ingests Seurat objects with TCR metadata, quantifies TCR clones via tcrClustR, merges clone information across samples, and trains a BertTCR MIL model for subject-level classification from TCR repertoire features. GPU required.

---

## Stage-by-stage dataflow

| Stage | Module | Input | Output | Compute |
|---|---|---|---|---|
| INGEST | `rdiscvr/ingest_*` | LabKey / URL / local file | `{sample_id}.rds` | CPU |
| QUANTIFY_TCR | `mil_ton/quantify_tcr` | Seurat RDS (with TRA/TRB columns) | `{sample_id}_tcr.rds`, `{sample_id}_tcr_metadata.csv` | CPU |
| MERGE_TCR_METADATA | `mil_ton/merge_tcr_metadata` | Collected TCR CSVs | `merged_tcr_metadata.csv` | CPU |
| TRAIN_TCR_MIL | `mil_ton/train_tcr_mil` | `merged_tcr_metadata.csv` | Trained BertTCR MIL model + predictions | GPU |

---

## Container images

- `ghcr.io/bimberlabinternal/tcrclustr:latest` — tcrClustR clone quantification (R)
- `ghcr.io/gwmcelfresh/mil-ton:latest` — MIL training (Python)

---

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `--tcrChains` | `TRA,TRB` | TCR chains to quantify |
| `--tcrOrganism` | `human` | Organism for germline V/J gene reference |
| `--bert_model` | `Rostlab/prot_bert` | BERT model for TCR sequence embedding |
| `--tcrMilEpochs` | `100` | MIL training epochs |
| `--tcrMilLR` | `3e-5` | MIL learning rate |

---

## Outputs

`outputs/tcr_mil/`:

| File | Description |
|---|---|
| `merged_tcr_metadata.csv` | All-sample TCR clone metadata |
| `tcr_mil_model.pt` | Trained BertTCR MIL checkpoint |
| `tcr_mil_predictions.csv` | Per-subject predictions and attention weights |

---

## Running locally

```bash
bash template/gw/run.sh --workflow tcr_mil
```

Requires a Seurat object with TRA/TRB CDR3 columns. For test data, run `fetch_example_data.sh` which injects synthetic TCR columns.

For the generated code-level reference, see [API Reference → Workflows](../api/generated/workflows.md#tcr-mil-pipeline).
