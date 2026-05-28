---
name: 16-evolve
description: Manage GoodWorkflows evolve cycles for adding or refactoring saved workflows, modules, templates, docs, CI, or launcher behavior. Includes base-image ad-hoc dependency patterns with uv (Python) and uvr (R).
---

# 16 Evolve

Use this when the user asks to add a workflow, add several workflow features, or substantially refactor a workflow surface.

## Cycle Setup

- Create or resume an evolve cycle in `workflow-state.yaml`.
- Capture feature IDs, affected surfaces, intended stage path, and verification target.
- Prefer one evolve cycle for related workflow/module/docs/CI changes.

## Delta Mode

Numbered stages 00-13 can run in delta mode for an active evolve cycle. Only redo the stage details affected by the requested change.

## GoodWorkflows Evolve Defaults

- Add workflow lists and docs together.
- Add samplesheet generation with workflow implementation.
- Add stub-run coverage before real-run expectations.
- Replace unshipped branch behavior directly; do not preserve compatibility with current-branch mistakes.

## Base Image and Ad-Hoc Dependencies

The repo publishes a multi-runtime base image (`ghcr.io/gwmcelfresh/goodworkflows:latest`) built from `Dockerfile` and validated by `.github/workflows/docker-publish.yml`. It ships **Python + [`uv`](https://github.com/astral-sh/uv)**, **R + [`uvr`](https://github.com/nbafrank/uvr)**, and **Rust**.

Use this image during evolve cycles when you need quick dependency experiments **without** rebuilding module container images (`rdiscvr`, `cellmembrane`, `scmodal`). Module containers remain the source of truth for production Nextflow processes; the base image is for prototyping, one-off scripts, and CI/tooling smoke checks.

### Python — ad-hoc with `uv`

- System Python is preconfigured (`UV_SYSTEM_PYTHON=1`).
- One-shot install: `uv pip install --system <pkg>`
- Isolated venv (preferred for scratch work):

```bash
uv venv /tmp/venv
source /tmp/venv/bin/activate
uv pip install pandas scanpy
python analysis.py
```

- For reproducible evolve artifacts, prefer a `pyproject.toml` + lockfile and document the chosen pattern in requirements or tech plan before merge.

### R — ad-hoc with `uvr`

- `uvr` is on `PATH`; system R is also available for legacy `install.packages()` calls.
- Project-scoped, lockfile-first workflow (mirrors `uv`):

```bash
uvr init my-analysis --r-version ">=4.3.0"
uvr add ggplot2 dplyr
uvr sync
uvr run analysis.R
```

- Per-project R versions without sudo: `uvr r install 4.4.2`, `uvr r use`, `uvr r pin`
- CI-style reproducibility: `uvr sync --frozen`
- Linux system libs: `uvr doctor` and `uvr sync` surface missing apt packages; the base `Dockerfile` already includes common R build deps (harfbuzz, freetype, libxml2, etc.).

### When to Escalate Beyond Ad-Hoc

- **Stay on base image + uv/uvr** — dependency probing, template drafts, docs examples, evolve-cycle spikes.
- **Move to a dedicated module container** — a dependency is required by a saved workflow process, must run under Nextflow container profiles, or needs GPU/CUDA pinning.
- **Touch `Dockerfile` / `docker-publish.yml`** — base runtime versions change, new system libraries are needed broadly, or CI smoke for the base image must expand.

### Dockerfile Pitfalls (from base-image CI)

- Do **not** use `add-apt-repository` for deadsnakes inside Docker; use explicit `/etc/apt/keyrings` + `sources.list.d` entries.
- Install `uvr` from GitHub release tarballs; select arch via `TARGETARCH` (`x86_64-unknown-linux-gnu` / `aarch64-unknown-linux-gnu`).

## Output

Update cycle status, current stage, touched surfaces, and next step. When ad-hoc uv/uvr experiments inform production deps, record the decision and whether the spike stays ephemeral or becomes a container/image change.
