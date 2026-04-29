// =============================================================================
// Channel Analyzer — detects .collect(), fan-in/out, channel types
// =============================================================================

import { ParsedWorkflow, WorkflowStatement, ChannelStructure } from '../types.js';

/**
 * Analyze channel flow through a parsed workflow.
 * Detects: .collect() points, fan-in, fan-out, channel types.
 */
export function analyzeChannels(workflow: ParsedWorkflow): {
  channels: ChannelStructure[];
  collectPoints: string[];
  fanInPoints: { node: string; sources: string[] }[];
  fanOutPoints: { node: string; targets: string[] }[];
} {
  const channels: ChannelStructure[] = [];
  const collectPoints: string[] = [];
  const processInputs = new Map<string, string[]>(); // process -> input channels
  const processOutputs = new Map<string, string[]>(); // process -> output channels
  const channelSources = new Map<string, string>(); // channel -> source process
  const channelTargets = new Map<string, string[]>(); // channel -> target processes

  for (const stmt of workflow.main) {
    if (stmt.type === 'call' && stmt.process && stmt.inputs) {
      // Track which channels feed into this process
      processInputs.set(stmt.process, stmt.inputs);
      for (const input of stmt.inputs) {
        if (!channelTargets.has(input)) channelTargets.set(input, []);
        channelTargets.get(input)!.push(stmt.process);
      }
    }

    if (stmt.type === 'assign' && stmt.target && stmt.process && stmt.outputs) {
      // Track which process produces this channel
      channelSources.set(stmt.target, stmt.process);
      if (!processOutputs.has(stmt.process)) processOutputs.set(stmt.process, []);
      processOutputs.get(stmt.process)!.push(stmt.target);

      // Build channel structure
      channels.push({
        name: stmt.target,
        type: 'channel',
        source: stmt.process,
        targets: [],
      });
    }

    if (stmt.type === 'collect' && stmt.target) {
      collectPoints.push(stmt.target);
    }
  }

  // Resolve channel targets
  for (const ch of channels) {
    const targets = channelTargets.get(ch.name) || [];
    ch.targets = targets;
  }

  // Detect fan-in (multiple sources feeding one process)
  const fanInPoints: { node: string; sources: string[] }[] = [];
  for (const [process, inputs] of processInputs) {
    const resolvedSources = inputs
      .map(input => channelSources.get(input))
      .filter((s): s is string => s !== undefined);
    const uniqueSources = [...new Set(resolvedSources)];
    if (uniqueSources.length > 1) {
      fanInPoints.push({ node: process, sources: uniqueSources });
    }
  }

  // Detect fan-out (one process output feeding multiple processes)
  const fanOutPoints: { node: string; targets: string[] }[] = [];
  for (const [process, outputs] of processOutputs) {
    const allTargets: string[] = [];
    for (const output of outputs) {
      const targets = channelTargets.get(output) || [];
      allTargets.push(...targets);
    }
    const uniqueTargets = [...new Set(allTargets)];
    if (uniqueTargets.length > 1) {
      fanOutPoints.push({ node: process, targets: uniqueTargets });
    }
  }

  return { channels, collectPoints, fanInPoints, fanOutPoints };
}

/**
 * Detect independent branches in a workflow.
 * A branch is a set of processes that don't share channels with the main pipeline.
 */
export function detectBranches(workflow: ParsedWorkflow): { name: string; nodes: string[]; description: string }[] {
  const branches: { name: string; nodes: string[]; description: string }[] = [];

  // Look for the TABULATE path which is independent
  const tabulateNodes: string[] = [];
  let hasTabulate = false;

  for (const stmt of workflow.main) {
    if (stmt.type === 'call' && stmt.process) {
      if (stmt.process === 'TABULATE' || stmt.process === 'INGEST_METADATA') {
        tabulateNodes.push(stmt.process);
        hasTabulate = true;
      }
    }
  }

  if (hasTabulate) {
    branches.push({
      name: 'metadata_only',
      nodes: tabulateNodes,
      description: 'Independent metadata tabulation branch that runs in parallel with the main pipeline',
    });
  }

  return branches;
}

/**
 * Detect GPU requirements from workflow statements.
 */
export function detectGpuRequirements(
  workflow: ParsedWorkflow,
  moduleGpuMap: Map<string, boolean>
): string[] {
  const gpuNodes: string[] = [];

  for (const stmt of workflow.main) {
    if (stmt.type === 'call' && stmt.process) {
      if (moduleGpuMap.get(stmt.process)) {
        gpuNodes.push(stmt.process);
      }
    }
  }

  return gpuNodes;
}