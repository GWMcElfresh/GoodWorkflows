# GoodWorkflows notebooks

Interactive templates for exploring pipeline outputs and debugging failed Nextflow tasks from a run’s `work/` directory.

---

## Local Python environment and kernel

Use a dedicated venv under `notebooks/` so Jupyter picks up the debug helpers without touching system Python.

```bash
cd notebooks
python3 -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -U pip
pip install -r requirements-notebooks.txt
python -m ipykernel install --user \
  --name goodworkflows-notebooks \
  --display-name "GoodWorkflows (notebooks venv)"
```

In VS Code, Cursor, or Jupyter Lab, open a notebook and choose kernel **GoodWorkflows (notebooks venv)**.

After changing `requirements-notebooks.txt`, reactivate the venv and run `pip install -r requirements-notebooks.txt` again. Re-run `ipykernel install` only if you recreate the venv at a new path.

---

## R kernel (exploratory R Markdown)

For [`templates/exploratory-analysis.Rmd`](templates/exploratory-analysis.Rmd), register an R kernel once (outside the Python venv):

```r
install.packages("IRkernel")
IRkernel::installspec(
  name = "goodworkflows-r",
  displayname = "GoodWorkflows (R)"
)
```

Use your usual R library path for `Seurat`, `Rdiscvr`, `edgeR`, etc. This repo does not ship an renv lockfile for R.

---

## Run directory layout

GoodWorkflows runs (e.g. from [`template/gw/run.sh`](../template/gw/run.sh)) look like:

```text
<run_dir>/
├── logs/nextflow.log
├── outputs/          # published results
└── work/             # per-task hash dirs (.command.sh, .command.err, …)
```

Local GPU launches maintain `template/gw/runs/latest` → most recent run. Point notebook parameters at that symlink or at any absolute run path.

---

## Templates

| File | Use |
|------|-----|
| [`templates/nextflow-work-debug.ipynb`](templates/nextflow-work-debug.ipynb) | List failed tasks, inspect `.command.*`, compare `outputs/` |
| [`templates/exploratory-analysis.Rmd`](templates/exploratory-analysis.Rmd) | Generic R scaffold for metadata / Seurat / pseudobulk work |

**Workflow:** copy a template into [`examples/`](examples/) (or your own folder), rename it, set `RUN_DIR` / `params$run_dir`, then run.

## Skills and debugging conventions (audit)

Cursor skills under [`.cursor/skills/`](../.cursor/skills/) target **agents** building or fixing the repo. Notebooks target **you** inspecting a finished or failed run on disk. Use this map so notebooks stay aligned with repo practice without duplicating full skill text.

### Use notebooks for

| Task | Where in the run |
|------|------------------|
| Find which task failed | `work/<hash>/.exitcode`, `.command.err` — [`nextflow-work-debug.ipynb`](templates/nextflow-work-debug.ipynb) |
| Read rendered command | `work/<hash>/.command.sh` (Groovy-rendered template output) |
| Compare staged vs published | `work/<hash>/` vs `<run_dir>/outputs/` |
| Explore RDS / tables after success | [`exploratory-analysis.Rmd`](templates/exploratory-analysis.Rmd) + [`docs/data-formats.md`](../docs/data-formats.md) |
| Tail orchestrator log | `<run_dir>/logs/nextflow.log` |
| HTML run summary | `<run_dir>/logs/report.html` (after completion) |

### Debug order (from [`14-hotfix`](../.cursor/skills/14-hotfix/SKILL.md) + [`goodworkflows-template-runtime`](../.cursor/skills/goodworkflows-template-runtime/SKILL.md))

1. Open `nextflow.log` and find the **first** real exception (read from the **bottom** upward).
2. In the failing `work/<hash>/`, inspect `.command.err` then `.command.sh`.
3. Classify the failure: template runtime, DSL2/channel, config/resources, launcher/samplesheet, or fixture data — then fix in repo source, not inside `work/`.
4. If a template fix “does nothing” on resume, delete that task’s hash dir or clear `work/` before re-running (Nextflow may reuse stale work).
5. **HPC / Apptainer:** reproducing container-only failures (Numba cache, read-only image) requires `apptainer exec <sif> ...` on the cluster — host notebooks do not run inside task containers. See [`goodworkflows-template-runtime/reference.md`](../.cursor/skills/goodworkflows-template-runtime/reference.md).

### Symptoms often visible in `.command.sh` / stderr

| Symptom | Likely surface | Skill / doc |
|---------|----------------|-------------|
| `SyntaxError: unterminated string literal` in `.command.sh` | Groovy stripped `\n`/`\t` in a Python template | [`goodworkflows-dsl2-validation/reference.md`](../.cursor/skills/goodworkflows-dsl2-validation/reference.md) |
| `token recognition error` / bare `$` in rendered script | Unescaped `$` in R/Python template | `goodworkflows-template-runtime` |
| AnnData / HDF5 string write errors | `obs` dtypes before `write_h5ad` | `goodworkflows-template-runtime/reference.md` |
| OOM during harmonize/merge | Accidental densification of sparse counts | [`goodworkflows-repo-context`](../.cursor/skills/goodworkflows-repo-context/SKILL.md) (sparse ownership) |
| `ingest_tabulate` / empty cell-type columns on local smoke | Stale `template/gw` example metadata | [`10-e2e/reference.md`](../.cursor/skills/10-e2e/reference.md) — regenerate via `fetch_example_data.sh` |

Full DSL2/parser tables live in agent skills; notebooks only need the work-dir evidence trail.

### Run directory paths to set in templates

| Launch style | Typical `RUN_DIR` / `params$run_dir` |
|--------------|--------------------------------------|
| `template/gw/run.sh` | `template/gw/runs/latest` (symlink) or `template/gw/runs/<workflow>_<timestamp>` |
| Copied `runs/my_run/` on HPC | Absolute path to that run folder |
| Repo-root `slurm_nextflow.sh` | Repo root ( `./work`, `./outputs`, `./logs` ) — not `runs/latest` |

From [`goodworkflows-repo-context`](../.cursor/skills/goodworkflows-repo-context/SKILL.md): local launchers aim for predictable `logs/`, `outputs/`, `work/`, and a **latest** pointer under `template/gw/runs/`.

### Published outputs by workflow (exploratory Rmd)

Check [`docs/workflows/`](../docs/workflows/) and [`docs/data-formats.md`](../docs/data-formats.md) before assuming paths under `outputs/`. Examples:

- `ingest_export` / integration ingest: `outputs/ingest/<sample_id>.rds`
- `ingest_tabulate`: `outputs/tabulate/subjectIdTable.csv` — see [`docs/vignettes/synthetic-tabulation.md`](../docs/vignettes/synthetic-tabulation.md)

### Agent-only skills (not notebook workflows)

No need to track these inside `notebooks/`; use Cursor Agent or CI instead:

- [`debug-github-actions-pr`](../.cursor/skills/debug-github-actions-pr/SKILL.md) — PR check logs, not local `work/`
- [`grill-me`](../.cursor/skills/grill-me/SKILL.md) / `requirements-grill/` — requirements Q&A before implementation
- [`goodworkflows-template-parity`](../.cursor/skills/goodworkflows-template-parity/SKILL.md) — launcher/CI registry parity when **changing** the repo
- [`pipeline`](../.cursor/skills/pipeline/SKILL.md) / `workflow-state.yaml` — tracked multi-stage implementation
- [`18-host-test`](../.cursor/skills/18-host-test/SKILL.md) — host profiles via `template/gw/check_workflows.sh`

When editing modules or templates in the repo, agents should still follow `14-hotfix` → domain skills; use notebooks to **gather evidence** from a run, then apply fixes in source and re-launch Nextflow.

---

## What not to commit

- `notebooks/.venv/`
- `notebooks/**/.ipynb_checkpoints/`
- `notebooks/scratch/`
- Large RDS / h5ad under `examples/` (use `.gitignore` locally if needed)

Pipeline artifacts (`work/`, `outputs/`, `runs/`) are already gitignored at the repo root.
