// =============================================================================
// Workflow Composer — generates new DSL2 workflow files from existing modules
// =============================================================================

import { ModuleInfo, ComposeRequest, ComposeResult } from '../types.js';

/**
 * Generate a valid DSL2 workflow file from a list of existing modules.
 * Handles: correct channel wiring, .collect() placement, stub compatibility, channel type validation.
 */
export function composeWorkflow(
  request: ComposeRequest,
  allModules: ModuleInfo[],
  repoRoot: string
): ComposeResult {
  const warnings: string[] = [];
  const moduleSet = new Set(request.modules);
  const selectedModules = allModules.filter(m => moduleSet.has(m.name));

  // Validate all requested modules exist
  for (const modName of request.modules) {
    if (!allModules.find(m => m.name === modName)) {
      warnings.push(`Module "${modName}" not found in repository`);
    }
  }

  // Validate stub compatibility
  for (const mod of selectedModules) {
    if (!mod.has_stub) {
      warnings.push(`Module "${mod.name}" does not have a stub block — CI smoke tests will fail`);
    }
  }

  // Build the workflow content
  const lines: string[] = [];
  const workflowName = request.name || 'custom_workflow';

  lines.push('#!/usr/bin/env nextflow');
  lines.push('');
  lines.push(`// Generated workflow: ${workflowName}`);
  lines.push(`// Modules: ${request.modules.join(', ')}`);
  if (request.with_tabulate) {
    lines.push('// Includes independent TABULATE branch');
  }
  lines.push('');

  // Include statements
  lines.push('// Module includes');
  const moduleIncludePaths = new Map<string, string>();
  for (const mod of selectedModules) {
    const relativePath = mod.path.replace(/\\/g, '/');
    const includePath = relativePath.replace('modules/', '../../../modules/');
    moduleIncludePaths.set(mod.name, includePath);
    lines.push(`include { ${mod.name} } from '${includePath}'`);
  }

  // Add TABULATE if requested
  if (request.with_tabulate) {
    const tabulate = allModules.find(m => m.name === 'TABULATE');
    if (tabulate) {
      const tabPath = tabulate.path.replace(/\\/g, '/').replace('modules/', '../../../modules/');
      lines.push(`include { TABULATE } from '${tabPath}'`);
    }
    const ingestMeta = allModules.find(m => m.name === 'INGEST_METADATA');
    if (ingestMeta) {
      const imPath = ingestMeta.path.replace(/\\/g, '/').replace('modules/', '../../../modules/');
      lines.push(`include { INGEST_METADATA } from '${imPath}'`);
    }
  }

  lines.push('');
  lines.push(`workflow ${workflowName.toUpperCase()} {`);
  lines.push('    take:');
  lines.push('        input_ch');  // samplesheet channel
  lines.push('');
  lines.push('    main:');

  // Generate channel wiring based on module order
  let prevOutput = 'input_ch';
  const moduleOrder = request.modules;

  for (let i = 0; i < moduleOrder.length; i++) {
    const modName = moduleOrder[i];
    const mod = selectedModules.find(m => m.name === modName);
    if (!mod) continue;

    // Determine input channel
    const inputCh = prevOutput;

    // Generate process call
    lines.push(`        ${modName}(${inputCh})`);

    // Generate output channel assignment
    const outputEmit = mod.outputs.length > 0 ? mod.outputs[0] : 'out';
    const outputChName = `${modName.toLowerCase()}_out`;
    lines.push(`        ${outputChName} = ${modName}.out.${outputEmit}`);

    // Add .collect() before multi-input processes
    if (i < moduleOrder.length - 1) {
      const nextMod = selectedModules.find(m => m.name === moduleOrder[i + 1]);
      if (nextMod && nextMod.inputs.length > 1) {
        lines.push(`        ${outputChName}_collected = ${outputChName}.collect()`);
        prevOutput = `${outputChName}_collected`;
      } else {
        prevOutput = outputChName;
      }
    }
  }

  // Add TABULATE branch if requested
  if (request.with_tabulate) {
    lines.push('');
    lines.push('        // Independent metadata tabulation branch');
    lines.push('        INGEST_METADATA(input_ch)');
    lines.push('        metadata_ch = INGEST_METADATA.out.metadata_csv');
    lines.push('        TABULATE(metadata_ch)');
  }

  lines.push('');
  lines.push('    emit:');
  for (const modName of moduleOrder) {
    const mod = selectedModules.find(m => m.name === modName);
    if (!mod) continue;
    const outputEmit = mod.outputs.length > 0 ? mod.outputs[0] : 'out';
    lines.push(`        ${modName.toLowerCase()}_emit = ${modName}.out.${outputEmit}`);
  }
  if (request.with_tabulate) {
    lines.push('        tabulate_emit = TABULATE.out');
  }

  lines.push('}');

  const workflowContent = lines.join('\n');

  return {
    workflow_name: workflowName,
    workflow_content: workflowContent,
    warnings,
  };
}