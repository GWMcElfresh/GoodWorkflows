// =============================================================================
// Param Suggester — suggests params based on workflow + data context
// =============================================================================

import { ParamSuggestion, SamplesheetAnalysis } from '../types.js';

/**
 * Suggest Nextflow parameters based on the selected workflow and input data.
 * Suggests: --export_assay, scMODAL params, tabulate columns.
 */
export function suggestParams(
  workflowName: string,
  samplesheetAnalysis: SamplesheetAnalysis,
  existingParams: Record<string, string>
): ParamSuggestion {
  const notes: string[] = [];
  const suggestion: ParamSuggestion = { notes: [] };

  // Suggest export_assay based on workflow
  if (workflowName === 'integration' || workflowName === 'ingest_export') {
    if (!existingParams['export_assay']) {
      suggestion.export_assay = 'RNA'; // Default for scRNA-seq
      notes.push('Defaulting --export_assay to "RNA" for scRNA-seq data');
    }
  }

  // Suggest scMODAL params for integration workflow
  if (workflowName === 'integration') {
    const scmodalParams: Record<string, string | number> = {};

    if (!existingParams['scmodal_latent']) {
      scmodalParams['scmodal_latent'] = 20;
      notes.push('Default scmodal_latent=20 (latent dimensions)');
    }
    if (!existingParams['scmodal_training_steps']) {
      scmodalParams['scmodal_training_steps'] = 10000;
      notes.push('Default scmodal_training_steps=10000');
    }
    if (!existingParams['scmodal_batch_size']) {
      scmodalParams['scmodal_batch_size'] = 500;
      notes.push('Default scmodal_batch_size=500');
    }
    if (!existingParams['scmodal_neighbors']) {
      scmodalParams['scmodal_neighbors'] = 30;
      notes.push('Default scmodal_neighbors=30');
    }
    if (!existingParams['leiden_resolution']) {
      scmodalParams['leiden_resolution'] = 0.5;
      notes.push('Default leiden_resolution=0.5');
    }

    // If running locally without GPU, suggest CPU mode
    if (!existingParams['scmodal_use_cpu']) {
      notes.push('Consider --scmodal_use_cpu=true if running without GPU');
    }

    if (Object.keys(scmodalParams).length > 0) {
      suggestion.scmodal_params = scmodalParams;
    }
  }

  // Suggest tabulate columns based on species mix
  if (samplesheetAnalysis.species_mix) {
    suggestion.tabulate_id_cols = ['cDNA_ID', 'SubjectId', 'Vaccine', 'Timepoint', 'Tissue'];
    notes.push('Multi-species experiment detected — suggested ID columns for tabulation');

    if (!existingParams['species_order']) {
      notes.push('Consider setting --species_order to control processing order');
    }
  }

  // Suggest tabulate columns for tabulate workflow
  if (workflowName === 'ingest_tabulate') {
    suggestion.tabulate_columns = ['RIRA_Immune.cellclass', 'RIRA_TNK_v2.cellclass', 'RIRA_Myeloid_v3.cellclass'];
    notes.push('Suggested standard RIRA cell-type columns for tabulation');
  }

  // Warn about harmonization needs
  if (samplesheetAnalysis.needs_harmonization && workflowName !== 'integration') {
    notes.push('Multiple species detected — consider using the "integration" workflow which includes gene harmonization');
  }

  suggestion.notes = notes;
  return suggestion;
}