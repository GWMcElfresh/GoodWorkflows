// =============================================================================
// DSL2 Workflow Parser — parses .nf workflow files
// =============================================================================

import * as fs from 'fs';
import * as path from 'path';
import { ParsedWorkflow, WorkflowStatement } from '../types.js';

/**
 * Parse a DSL2 workflow file and extract its structure.
 * Handles: include statements, workflow { take:/main:/emit: } blocks,
 * process calls, .collect(), .map{}, channel assignments.
 */
export function parseWorkflowFile(filePath: string): ParsedWorkflow {
  const content = fs.readFileSync(filePath, 'utf-8');
  const lines = content.split('\n');

  const includes: { module_name: string; path: string }[] = [];
  const takes: { name: string; type: string }[] = [];
  const main: WorkflowStatement[] = [];
  const emits: { name: string; source: string }[] = [];

  let workflowName = path.basename(filePath, '.nf');

  // Parse include statements
  for (const line of lines) {
    const trimmed = line.trim();

    // include { MODULE_NAME } from 'path'
    const includeMatch = trimmed.match(/include\s*\{\s*(\w+)\s*\}\s*from\s*['"](.+?)['"]/);
    if (includeMatch) {
      includes.push({ module_name: includeMatch[1], path: includeMatch[2] });
    }

    // include { MODULE_NAME as ALIAS } from 'path'
    const includeAliasMatch = trimmed.match(/include\s*\{\s*(\w+)\s+as\s+(\w+)\s*\}\s*from\s*['"](.+?)['"]/);
    if (includeAliasMatch) {
      includes.push({ module_name: includeAliasMatch[2], path: includeAliasMatch[3] });
    }
  }

  // Find workflow block
  const workflowBlockRegex = /workflow\s+(\w*)\s*\{/;
  let inWorkflow = false;
  let inTake = false;
  let inMain = false;
  let inEmit = false;
  let braceDepth = 0;

  for (const line of lines) {
    const trimmed = line.trim();

    // Detect workflow block start
    const wfMatch = trimmed.match(workflowBlockRegex);
    if (wfMatch && !inWorkflow) {
      inWorkflow = true;
      if (wfMatch[1]) workflowName = wfMatch[1];
      braceDepth = 1;
      continue;
    }

    if (!inWorkflow) continue;

    // Track braces
    const openBraces = (trimmed.match(/\{/g) || []).length;
    const closeBraces = (trimmed.match(/\}/g) || []).length;
    braceDepth += openBraces - closeBraces;

    if (braceDepth <= 0) {
      inWorkflow = false;
      inTake = false;
      inMain = false;
      inEmit = false;
      break;
    }

    // Detect sections
    if (trimmed.startsWith('take:')) {
      inTake = true;
      inMain = false;
      inEmit = false;
      continue;
    }
    if (trimmed.startsWith('main:')) {
      inTake = false;
      inMain = true;
      inEmit = false;
      continue;
    }
    if (trimmed.startsWith('emit:')) {
      inTake = false;
      inMain = false;
      inEmit = true;
      continue;
    }

    if (inTake) {
      // Parse channel input declarations
      const takeMatch = trimmed.match(/^(\w+)\s*$/);
      if (takeMatch) {
        takes.push({ name: takeMatch[1], type: 'channel' });
      }
    }

    if (inMain) {
      const stmt = parseMainStatement(trimmed);
      if (stmt) main.push(stmt);
    }

    if (inEmit) {
      // emit_name = process.out
      const emitMatch = trimmed.match(/^(\w+)\s*=\s*(\w+)\.(\w+)/);
      if (emitMatch) {
        emits.push({ name: emitMatch[1], source: `${emitMatch[2]}.${emitMatch[3]}` });
      }
    }
  }

  return { name: workflowName, includes, takes, main, emits };
}

function parseMainStatement(line: string): WorkflowStatement | null {
  const trimmed = line.trim();
  if (!trimmed || trimmed.startsWith('//') || trimmed.startsWith('/*')) return null;

  // .collect() call: channel.collect()
  const collectMatch = trimmed.match(/(\w+)\.collect\(\)/);
  if (collectMatch) {
    return {
      type: 'collect',
      target: collectMatch[1],
      raw: trimmed,
    };
  }

  // .map{} call: channel.map{ ... }
  const mapMatch = trimmed.match(/(\w+)\.map\s*\{/);
  if (mapMatch) {
    return {
      type: 'map',
      target: mapMatch[1],
      raw: trimmed,
    };
  }

  // Process call: PROCESS_NAME(input_channel, ...)
  const callMatch = trimmed.match(/^(\w+)\((.+?)\)\s*$/);
  if (callMatch) {
    const processName = callMatch[1];
    const argsStr = callMatch[2];
    const inputs = argsStr.split(',').map(a => a.trim()).filter(a => a.length > 0);
    return {
      type: 'call',
      process: processName,
      inputs,
      raw: trimmed,
    };
  }

  // Channel assignment: channel_name = PROCESS.out
  const assignMatch = trimmed.match(/^(\w+)\s*=\s*(\w+)\.(\w+)/);
  if (assignMatch) {
    return {
      type: 'assign',
      target: assignMatch[1],
      process: assignMatch[2],
      outputs: [assignMatch[3]],
      raw: trimmed,
    };
  }

  // Channel assignment with .collect(): ch = PROCESS.out.collect()
  const assignCollectMatch = trimmed.match(/^(\w+)\s*=\s*(\w+)\.(\w+)\.collect\(\)/);
  if (assignCollectMatch) {
    return {
      type: 'assign',
      target: assignCollectMatch[1],
      process: assignCollectMatch[2],
      outputs: [assignCollectMatch[3]],
      raw: trimmed,
    };
  }

  return null;
}

/**
 * Discover all workflow files in the workflows/ directory.
 */
export function discoverWorkflowFiles(repoRoot: string): string[] {
  const workflowsDir = path.join(repoRoot, 'workflows');
  if (!fs.existsSync(workflowsDir)) return [];

  return fs.readdirSync(workflowsDir)
    .filter(f => f.endsWith('.nf'))
    .map(f => path.join(workflowsDir, f));
}

/**
 * Parse main.nf to discover the workflow switch block and available workflows.
 */
export function parseMainSwitch(repoRoot: string): { workflows: string[]; default_workflow: string } {
  const mainPath = path.join(repoRoot, 'main.nf');
  if (!fs.existsSync(mainPath)) return { workflows: [], default_workflow: '' };

  const content = fs.readFileSync(mainPath, 'utf-8');
  const workflows: string[] = [];
  let defaultWorkflow = '';

  // Find workflow names in the switch block
  const switchMatch = content.match(/switch\s*\(\s*params\.workflow\s*\)\s*\{([^}]+)\}/s);
  if (switchMatch) {
    const switchBody = switchMatch[1];
    const caseMatches = switchBody.matchAll(/case\s+['"]([^'"]+)['"]/g);
    for (const m of caseMatches) {
      workflows.push(m[1]);
    }
  }

  // Find default workflow from params
  const defaultMatch = content.match(/workflow\s*=\s*['"]([^'"]+)['"]/);
  if (defaultMatch) {
    defaultWorkflow = defaultMatch[1];
  }

  return { workflows, default_workflow: defaultWorkflow };
}