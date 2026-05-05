#!/usr/bin/env nextflow
/*
 * main.nf – thin entrypoint for saved GoodWorkflows DSL2 workflows.
 */

nextflow.enable.dsl = 2

include { INTEGRATION_PIPELINE } from './workflows/integration_pipeline.nf'
include { INGEST_EXPORT_PIPELINE } from './workflows/ingest_export.nf'
include { INGEST_TABULATE_PIPELINE } from './workflows/ingest_tabulate.nf'
include { NMF_VAE_PIPELINE } from './workflows/nmf_vae.nf'

workflow {
    main:
    supportedWorkflows = ['integration', 'ingest_export', 'ingest_tabulate', 'nmf_vae']

    if (params.help) {
        log.info """
        =========================================
         GoodWorkflows scRNA-seq Pipeline
        =========================================
        Usage:
          nextflow run main.nf -profile slurm [options]

        Saved workflows:
        --workflow integration     Full pipeline: ingest -> export -> harmonize -> scMODAL
        --workflow ingest_export  Fetch Seurat RDS and export 10x-like counts only
        --workflow ingest_tabulate  Fetch metadata only and build subjectIdTable
        --workflow nmf_vae        Fetch Seurat RDS, export counts, merge, and train NMF-VAE

        Defaults:
          --input FILE              Samplesheet CSV   [default: ${params.input}]
          --outdir DIR              Output directory  [default: ${params.outdir}]
          workDir                   Nextflow work dir [default: ${new File('.').absolutePath}/work via config]

        Required for current workflows:
          --labkey_base_url URL     Prime-seq / LabKey base URL used by Rdiscvr
          --labkey_folder PATH      Prime-seq / LabKey folder path used by Rdiscvr

        Optional:
          --species_order STR       Multi-species order [default: ${params.species_order}]
            --tabulate_id_cols STR    CSV of id columns [default: ${params.tabulate_id_cols}]
            --tabulate_celltype_cols STR  CSV of cell-type columns [default: ${params.tabulate_celltype_cols}]
            --tabulate_parent_col STR Parent lineage column [default: ${params.tabulate_parent_col}]
            --tabulate_celltype_parent_map STR  Cell-type:parentValue map [default: ${params.tabulate_celltype_parent_map}]
          --help                    Show this message

        Examples:
          nextflow run main.nf -profile slurm --workflow integration --labkey_base_url https://labkey.example.org --labkey_folder /My/Folder
          nextflow run main.nf -profile slurm --workflow ingest_export --outdir ./outputs/dev
                nextflow run main.nf -profile slurm --workflow ingest_tabulate --tabulate_id_cols cDNA_ID,SubjectId,Vaccine,Timepoint,Tissue
        """.stripIndent()
        exit 0
    }

    selectedWorkflow = (params.workflow ?: 'integration').toString().trim()

    if (!(selectedWorkflow in supportedWorkflows)) {
        error "Unsupported workflow '${selectedWorkflow}'. Valid options: ${supportedWorkflows.join(', ')}"
    }

    if (!params.input) {
        error "Please supply a samplesheet via --input. Run with --help for usage."
    }

    // LabKey params are only required when the samplesheet uses output_file_id.
    // URL-based and path-based samplesheets do not need LabKey credentials.
    // We defer the actual validation to the INGEST process, which checks at runtime.
    if (selectedWorkflow in ['integration', 'ingest_export', 'ingest_tabulate']) {
        if (!params.labkey_base_url || !params.labkey_folder) {
            log.warn """
            WARNING: --labkey_base_url and --labkey_folder are not set.
            If your samplesheet uses 'output_file_id' (LabKey mode), the pipeline will fail.
            If your samplesheet uses 'url' or 'path' mode, this warning can be ignored.
            """.stripIndent()
        }
    }

    if (selectedWorkflow == 'integration' && !params.species_order) {
        error "Please supply --species_order or use the default in nextflow.config."
    }

    if (selectedWorkflow == 'integration') {
        INTEGRATION_PIPELINE(params.input)
    } else if (selectedWorkflow == 'ingest_export') {
        INGEST_EXPORT_PIPELINE(params.input)
    } else if (selectedWorkflow == 'ingest_tabulate') {
        INGEST_TABULATE_PIPELINE(params.input)
    } else if (selectedWorkflow == 'nmf_vae') {
        NMF_VAE_PIPELINE(params.input)
    }

    onComplete:
    if (workflow.success) {
        log.info """
        Workflow            : ${params.workflow ?: 'integration'}
        Pipeline completed  : ${workflow.complete}
        Duration            : ${workflow.duration}
        Success             : ${workflow.success}
        Work directory      : ${workflow.workDir}
        Results directory   : ${params.outdir}
        Exit status         : ${workflow.exitStatus}
        """.stripIndent()
    } else {
        log.error "Pipeline failed: ${workflow.errorMessage}"
        log.error "Check logs/ for details and re-run with -resume to continue."
    }
}
