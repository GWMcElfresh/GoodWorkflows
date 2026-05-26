# GoodWorkflows Template Parity Reference

Detailed parity notes migrated from the retired root `skills/` directory.

## Source of Truth

- Workflows: `main.nf` `supportedWorkflows`.
- Container images: `scripts/image-manifest.txt`.
- Local launcher: `template/gw/`.
- Cluster launcher: `template/cluster/` when present.

## Image Parity

Keep these aligned:

- `scripts/image-manifest.txt`
- `template/gw/setup.sh`
- `scripts/ci/cache_container_images.sh`

Useful check:

```bash
grep -v '^#' scripts/image-manifest.txt | grep -v '^$' | sort
grep -oP '"ghcr\.io/[^"]+"' template/gw/setup.sh | sort
grep -oP '"ghcr\.io/[^"]+"' scripts/ci/cache_container_images.sh | sort
```

## Workflow Parity

Keep these aligned when a workflow changes:

- `main.nf`
- `nextflow_schema.json`
- `template/gw/run.sh`
- `template/gw/check_workflows.sh`
- `template/gw/fetch_example_data.sh`
- `.github/workflows/ci.yml`
- `scripts/ci/run_nextflow_smoke_tests.sh`
- `docs/workflows/*.md`
- `docs/index.md`
- `docs/parameters.md`
- `mkdocs.yml`
- `README.md`
- `memory-bank/workflows.md`

## Intentional Divergences

Do not erase these without a design decision:

- local profile/runtime: `local_gpu`, Podman, `--gpus all`
- cluster profile/runtime: `slurm_singularity`, SLURM, Apptainer SIF cache
- LabKey credentials required on cluster but not local test scaffolds
- SBATCH headers in cluster scripts
- ANSI color local logs vs plain SLURM logs
- Nextflow binary discovery differences

## Known Pitfalls

- SLURM param parsing must strip both single and double quotes.
- Podman bind mounts require existing host directories.
- GHCR image names may use hyphens while params use underscores.
- Directory is `template/`, not `templates/`.
- Avoid `workDir` in included configs when launchers pass `-work-dir`.
- `test` profile should include `base.config` before overrides.
