#!/usr/bin/env nextflow
/*
 * main.nf – scRNA-seq pipeline entry point (DSL2)
 *
 * Pipeline topology:
 *
 *   samplesheet (CSV)
 *        │
 *        ▼  (one SLURM job per sample, run in parallel)
 *   ┌─────────┐
 *   │  INGEST │  rdiscvr  – fetch raw 10x data, create Seurat RDS
 *   └────┬────┘
 *        │  tuple (sample_id, rds)
 *        ▼  (one SLURM job per sample, run in parallel)
 *   ┌──────────────────┐
 *   │  SEURAT_PROCESS  │  cellmembrane – QC, normalise, cluster, export h5ad
 *   └────────┬─────────┘
 *            │  collect all h5ad files from all samples
 *            ▼  (single GPU SLURM job)
 *   ┌─────────────────┐
 *   │   GPU_ANALYSIS  │  nmf-vae – minibatch NMF-VAE across full cohort
 *   └─────────────────┘
 *
 * Resume / checkpointing:
 *   Run with `-resume` (set by default in slurm_nextflow.sh).  Nextflow caches
 *   each completed task by its input hash; re-running after a partial failure
 *   skips already-completed tasks automatically.
 *
 * Stub / dry-run testing (no containers required):
 *   nextflow run main.nf -stub-run
 */

nextflow.enable.dsl = 2

// ---------------------------------------------------------------------------
// Module imports
// ---------------------------------------------------------------------------
include { INGEST           } from './modules/local/rdiscvr/ingest/main.nf'
include { SEURAT_PROCESS   } from './modules/local/cellmembrane/seurat/main.nf'
include { GPU_ANALYSIS     } from './modules/local/nmf_vae/gpu/main.nf'

// ---------------------------------------------------------------------------
// Help message
// ---------------------------------------------------------------------------
def helpMessage() {
    log.info """
    =========================================
     scRNA-seq Nextflow Pipeline
    =========================================
    Usage:
      nextflow run main.nf [options]

    Required:
      --input FILE        Samplesheet CSV with columns: sample_id, raw_data_path
                          Default: assets/samplesheet.csv

    Optional:
      --outdir DIR        Results directory  [default: results]
      --help              Show this message

    Environment variables (export before sbatch):
      NXF_WORK            Nextflow work directory (shared FS)
      NXF_PODMAN_CACHEDIR Existing Podman image store for image caching
      NXF_PODMAN_VOLUMES  Additional -v mounts passed to every container
    """.stripIndent()
}

if (params.help) {
    helpMessage()
    exit 0
}

// ---------------------------------------------------------------------------
// Input validation
// ---------------------------------------------------------------------------
if (!params.input) {
    error "Please supply a samplesheet via --input. Run with --help for usage."
}

// ---------------------------------------------------------------------------
// Workflow
// ---------------------------------------------------------------------------
workflow {

    // --- Build per-sample channel from samplesheet CSV ----------------------
    //
    // Expected CSV columns:   sample_id , raw_data_path
    // raw_data_path should be an absolute path on the shared filesystem.
    //
    ch_samples = Channel
        .fromPath(params.input, checkIfExists: true)
        .splitCsv(header: true, strip: true)
        .map { row ->
            def meta = [id: row.sample_id]
            def raw  = file(row.raw_data_path, checkIfExists: true)
            return tuple(meta, raw)
        }

    // --- Stage 1: data ingest (parallel, one job per sample) ----------------
    INGEST(ch_samples)

    // --- Stage 2: Seurat processing (parallel, one job per sample) ----------
    SEURAT_PROCESS(INGEST.out.rds)

    // --- Stage 3: GPU analysis (single job, all samples collected) ----------
    //
    // .map extracts only the h5ad path from the (meta, h5ad) tuple.
    // .collect() waits for ALL samples before submitting the GPU job.
    ch_all_h5ad = SEURAT_PROCESS.out.h5ad
        .map { _meta, h5ad -> h5ad }
        .collect()

    GPU_ANALYSIS(ch_all_h5ad)

    // --- Summary published results ------------------------------------------
    ch_all_h5ad
        .subscribe { log.info "Staged for GPU: ${it}" }
}

// ---------------------------------------------------------------------------
// Workflow lifecycle hooks
// ---------------------------------------------------------------------------
workflow.onComplete {
    log.info """
    Pipeline completed  : ${workflow.complete}
    Duration            : ${workflow.duration}
    Success             : ${workflow.success}
    Work directory      : ${workflow.workDir}
    Results directory   : ${params.outdir}
    Exit status         : ${workflow.exitStatus}
    """.stripIndent()
}

workflow.onError {
    log.error "Pipeline failed: ${workflow.errorMessage}"
    log.error "Check logs/ for details and re-run with -resume to continue."
}
