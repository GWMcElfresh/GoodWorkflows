// =============================================================================
// Pipeline Suggestion — suggests pipelines from goals + constraints
// =============================================================================

import { ModuleInfo, PipelineSuggestion } from '../types.js';

/**
 * Suggest a pipeline composition based on a goal and constraints.
 * Reuses existing modules, respects labels + resource classes, understands dual-branch design.
 */
export function suggestPipeline(
  goal: string,
  constraints: { profile?: string; no_gpu?: boolean },
  allModules: ModuleInfo[]
): PipelineSuggestion {
  const goalLower = goal.toLowerCase();
  const excluded: string[] = [];
  const workflowPlan: string[] = [];
  const warnings: string[] = [];
  let reasoning = '';

  // Determine which modules are available based on constraints
  const availableModules = allModules.filter(m => {
    if (constraints.no_gpu && m.is_gpu) {
      excluded.push(m.name);
      return false;
    }
    return true;
  });

  // Build suggestion based on goal keywords
  const needsIngest = goalLower.includes('ingest') || goalLower.includes('labkey') || goalLower.includes('import');
  const needsExport = goalLower.includes('export') || goalLower.includes('counts') || goalLower.includes('seurat');
  const needsHarmonize = goalLower.includes('harmonize') || goalLower.includes('cross-species') || goalLower.includes('gene');
  const needsIntegrate = goalLower.includes('integrate') || goalLower.includes('scmodal') || goalLower.includes('embedding');
  const needsTabulate = goalLower.includes('tabulate') || goalLower.includes('metadata') || goalLower.includes('report');
  const noGpu = goalLower.includes('without gpu') || goalLower.includes('no gpu') || constraints.no_gpu;

  // Always start with INGEST if data import is needed
  if (needsIngest || needsExport || needsHarmonize || needsIntegrate) {
    const ingest = availableModules.find(m => m.name === 'INGEST');
    if (ingest) {
      workflowPlan.push('INGEST');
    } else {
      warnings.push('INGEST module not available');
    }
  }

  // Add EXPORT_COUNTS
  if (needsExport || needsHarmonize || needsIntegrate) {
    const exportMod = availableModules.find(m => m.name === 'EXPORT_COUNTS');
    if (exportMod) {
      workflowPlan.push('EXPORT_COUNTS');
    } else {
      warnings.push('EXPORT_COUNTS module not available');
    }
  }

  // Add GENE_HARMONIZE
  if (needsHarmonize || needsIntegrate) {
    const harmonize = availableModules.find(m => m.name === 'GENE_HARMONIZE');
    if (harmonize) {
      workflowPlan.push('GENE_HARMONIZE');
    } else {
      warnings.push('GENE_HARMONIZE module not available');
    }
  }

  // Add SCMODAL_INTEGRATE (GPU-dependent)
  if (needsIntegrate) {
    const integrate = allModules.find(m => m.name === 'SCMODAL_INTEGRATE');
    if (integrate) {
      if (noGpu || (integrate.is_gpu && constraints.no_gpu)) {
        excluded.push('SCMODAL_INTEGRATE');
        reasoning = 'SCMODAL_INTEGRATE requires GPU but GPU is not available or was excluded';
        warnings.push('SCMODAL_INTEGRATE excluded — GPU required');
      } else {
        workflowPlan.push('SCMODAL_INTEGRATE');
      }
    }
  }

  // Add TABULATE (independent branch)
  if (needsTabulate) {
    const tabulate = availableModules.find(m => m.name === 'TABULATE');
    if (tabulate) {
      workflowPlan.push('TABULATE');
    } else {
      warnings.push('TABULATE module not available');
    }
  }

  // If no specific goal matched, suggest the full pipeline
  if (workflowPlan.length === 0) {
    for (const mod of availableModules) {
      workflowPlan.push(mod.name);
    }
    reasoning = 'No specific goal detected; suggesting all available modules';
  }

  if (!reasoning) {
    reasoning = `Pipeline composed for goal: "${goal}"`;
    if (noGpu) reasoning += ' (GPU excluded)';
    if (constraints.profile) reasoning += ` with profile: ${constraints.profile}`;
  }

  return {
    workflow_plan: workflowPlan,
    excluded,
    reasoning,
    warnings: warnings.length > 0 ? warnings : undefined,
  };
}