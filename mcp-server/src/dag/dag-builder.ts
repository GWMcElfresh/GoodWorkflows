// =============================================================================
// DAG Builder — builds a DAG from parsed workflows and modules
// =============================================================================

import * as path from 'path';
import { ParsedWorkflow, ParsedProcess, Dag, DagNode, DagEdge, DagBranch } from '../types.js';
import { analyzeChannels, detectBranches, detectGpuRequirements } from '../parser/channel-analyzer.js';

/**
 * Build a complete DAG from a parsed workflow and its module definitions.
 */
export function buildDag(
  workflow: ParsedWorkflow,
  modules: Map<string, ParsedProcess>,
  repoRoot: string
): Dag {
  const nodes: DagNode[] = [];
  const edges: DagEdge[] = [];
  const gpuNodes: string[] = [];

  const { channels, collectPoints, fanInPoints, fanOutPoints } = analyzeChannels(workflow);
  const branches = detectBranches(workflow);

  // Build module GPU map
  const moduleGpuMap = new Map<string, boolean>();
  for (const [name, proc] of modules) {
    moduleGpuMap.set(name, proc.is_gpu);
  }

  const detectedGpu = detectGpuRequirements(workflow, moduleGpuMap);

  // Add process nodes
  const addedProcesses = new Set<string>();
  for (const stmt of workflow.main) {
    if (stmt.type === 'call' && stmt.process && !addedProcesses.has(stmt.process)) {
      const proc = modules.get(stmt.process);
      const isGpu = proc?.is_gpu || detectedGpu.includes(stmt.process);

      nodes.push({
        id: stmt.process,
        type: 'process',
        label: proc?.label,
        is_gpu: isGpu,
        module_path: proc ? path.relative(repoRoot, path.dirname(path.dirname(proc.raw_body ? '' : ''))) : undefined,
      });

      if (isGpu) gpuNodes.push(stmt.process);
      addedProcesses.add(stmt.process);
    }
  }

  // Add collect nodes
  for (const cp of collectPoints) {
    nodes.push({
      id: `collect:${cp}`,
      type: 'collect',
    });
  }

  // Build edges from channel flow
  const addedEdges = new Set<string>();
  for (const ch of channels) {
    const sourceNode = ch.source;
    for (const target of ch.targets) {
      const edgeKey = `${sourceNode}->${target}`;
      if (!addedEdges.has(edgeKey)) {
        edges.push({
          from: sourceNode,
          to: target,
          channel_type: ch.type,
          is_collect: collectPoints.includes(ch.name),
        });
        addedEdges.add(edgeKey);
      }
    }
  }

  // Add edges for collect points
  for (const cp of collectPoints) {
    // Find which process produces this channel
    const sourceCh = channels.find(ch => ch.name === cp);
    if (sourceCh) {
      const collectNodeId = `collect:${cp}`;
      // Edge from source process to collect node
      edges.push({
        from: sourceCh.source,
        to: collectNodeId,
        is_collect: true,
      });
      // Edge from collect node to downstream processes
      for (const target of sourceCh.targets) {
        edges.push({
          from: collectNodeId,
          to: target,
          is_collect: true,
        });
      }
    }
  }

  return {
    nodes,
    edges,
    branches,
    collect_points: collectPoints,
    fan_in_points: fanInPoints,
    fan_out_points: fanOutPoints,
    gpu_nodes: gpuNodes,
  };
}

/**
 * Build a DAG for a specific workflow by name.
 */
export function buildDagForWorkflow(
  workflowName: string,
  workflows: Map<string, ParsedWorkflow>,
  modules: Map<string, ParsedProcess>,
  repoRoot: string
): Dag | null {
  const workflow = workflows.get(workflowName);
  if (!workflow) return null;

  return buildDag(workflow, modules, repoRoot);
}