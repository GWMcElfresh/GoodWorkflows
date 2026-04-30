#!/usr/bin/env node
// =============================================================================
// nextflow_workflows MCP Server — main entry point
// =============================================================================

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ErrorCode,
  ListToolsRequestSchema,
  McpError,
} from '@modelcontextprotocol/sdk/types.js';
import * as path from 'path';
import * as fs from 'fs';

// Parsers
import { parseWorkflowFile, discoverWorkflowFiles, parseMainSwitch } from './parser/workflow-parser.js';
import { parseProcessFile, discoverModuleDirs, moduleNameFromPath } from './parser/module-parser.js';
import { parseBaseConfig, buildProfileInfo } from './parser/config-parser.js';
import { analyzeChannels, detectBranches, detectGpuRequirements } from './parser/channel-analyzer.js';

// DAG
import { buildDag, buildDagForWorkflow } from './dag/dag-builder.js';

// Composition
import { suggestPipeline } from './composition/suggest-pipeline.js';
import { composeWorkflow } from './composition/compose-workflow.js';

// Execution
import { validateWorkflow } from './execution/validate-workflow.js';
import { runWorkflow, resumeRun } from './execution/run-workflow.js';

// Bio
import { analyzeSamplesheet } from './bio/analyze-samplesheet.js';
import { suggestParams } from './bio/suggest-params.js';

// Types
import {
  RepositoryDiscovery, WorkflowInfo, ModuleInfo, Dag, WorkflowDetails,
  PipelineSuggestion, ComposeRequest, ComposeResult, ValidationResult,
  RunRequest, RunResult, SamplesheetAnalysis, ParamSuggestion,
  ParsedWorkflow, ParsedProcess, ParamsInfo, ProfileInfo,
} from './types.js';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------
const REPO_ROOT = process.env.GOODWORKFLOWS_ROOT || path.resolve('.');

// ---------------------------------------------------------------------------
// Cache (lazy-loaded on first use)
// ---------------------------------------------------------------------------
let _cache: {
  workflows: Map<string, ParsedWorkflow>;
  modules: Map<string, ParsedProcess>;
  moduleInfos: ModuleInfo[];
  paramsInfo: ParamsInfo;
  profiles: ProfileInfo[];
  workflowNames: string[];
  defaultWorkflow: string;
} | null = null;

function getCache() {
  if (_cache) return _cache;

  // Parse all modules — first pass: parse process files
  const moduleDirs = discoverModuleDirs(REPO_ROOT);
  const processByName = new Map<string, ParsedProcess>(); // process name -> parsed process
  const processDirMap = new Map<string, string>(); // process name -> module dir path

  for (const dir of moduleDirs) {
    const mainPath = path.join(dir, 'main.nf');
    if (fs.existsSync(mainPath)) {
      const proc = parseProcessFile(mainPath);
      processByName.set(proc.name, proc);
      processDirMap.set(proc.name, dir);
    }
  }

  // Parse all workflows to discover module aliases (include { ALIAS } from '...')
  const workflowFiles = discoverWorkflowFiles(REPO_ROOT);
  const workflows = new Map<string, ParsedWorkflow>();
  const moduleAliasToProcess = new Map<string, string>(); // alias -> process name

  for (const wfFile of workflowFiles) {
    const parsed = parseWorkflowFile(wfFile);
    // Use filename stem as workflow name (e.g., ingest_export)
    const wfName = path.basename(wfFile, '.nf');
    parsed.name = wfName;
    workflows.set(wfName, parsed);

    // Map include aliases to process names
    for (const inc of parsed.includes) {
      // inc.module_name is the alias (e.g., EXPORT_COUNTS)
      // We need to find which process this maps to
      // The include path points to a module dir; parse that dir's main.nf to get the process name
      const includePath = inc.path;
      // Resolve relative path from the workflow file's directory
      const resolvedPath = path.resolve(path.dirname(wfFile), includePath);
      if (fs.existsSync(resolvedPath)) {
        const proc = parseProcessFile(resolvedPath);
        moduleAliasToProcess.set(inc.module_name, proc.name);
      }
    }
  }

  // Build modules map keyed by alias (the name used in workflows)
  const modules = new Map<string, ParsedProcess>();
  const moduleInfos: ModuleInfo[] = [];

  for (const [alias, processName] of moduleAliasToProcess) {
    const proc = processByName.get(processName);
    if (proc) {
      modules.set(alias, proc);

      const dir = processDirMap.get(processName) || '';
      const mainPath = path.join(dir, 'main.nf');
      const relPath = path.relative(REPO_ROOT, mainPath).replace(/\\/g, '/');
      moduleInfos.push({
        name: alias,
        path: relPath,
        inputs: proc.inputs.map(i => i.name),
        outputs: proc.outputs.map(o => o.emit || o.name),
        label: proc.label || '',
        has_stub: proc.has_stub,
        container: proc.container,
        is_gpu: proc.is_gpu,
        publish_dir: proc.publish_dir,
      });
    }
  }

  // Also add any modules not referenced by workflows (fallback)
  for (const [processName, proc] of processByName) {
    if (![...moduleAliasToProcess.values()].includes(processName)) {
      // Use process name as module name if not aliased
      if (!modules.has(processName)) {
        modules.set(processName, proc);
        const dir = processDirMap.get(processName) || '';
        const mainPath = path.join(dir, 'main.nf');
        const relPath = path.relative(REPO_ROOT, mainPath).replace(/\\/g, '/');
        moduleInfos.push({
          name: processName,
          path: relPath,
          inputs: proc.inputs.map(i => i.name),
          outputs: proc.outputs.map(o => o.emit || o.name),
          label: proc.label || '',
          has_stub: proc.has_stub,
          container: proc.container,
          is_gpu: proc.is_gpu,
          publish_dir: proc.publish_dir,
        });
      }
    }
  }

  // Parse main.nf switch
  const { workflows: wfNames, default_workflow: defaultWf } = parseMainSwitch(REPO_ROOT);

  // Parse configs
  const paramsInfo = parseBaseConfig(REPO_ROOT);
  const profiles = buildProfileInfo(REPO_ROOT);

  _cache = {
    workflows,
    modules,
    moduleInfos,
    paramsInfo,
    profiles,
    workflowNames: wfNames,
    defaultWorkflow: defaultWf,
  };

  return _cache;
}

// ---------------------------------------------------------------------------
// Tool implementations
// ---------------------------------------------------------------------------

function handleDiscoverRepository(): RepositoryDiscovery {
  const cache = getCache();

  const workflowInfos: WorkflowInfo[] = [];
  for (const [name, wf] of cache.workflows) {
    const stages = wf.main
      .filter(s => s.type === 'call' && s.process)
      .map(s => s.process!);
    const usesModules = wf.includes.map(i => i.module_name);
    const hasGpu = stages.some(s => cache.modules.get(s)?.is_gpu);

    workflowInfos.push({
      name,
      entrypoint: `${name}.nf`,
      stages,
      type: hasGpu ? 'mixed' : 'cpu',
      uses_modules: usesModules,
    });
  }

  return {
    workflows: workflowInfos,
    modules: cache.moduleInfos,
    profiles: cache.profiles.filter(p => p.is_active).map(p => p.name),
    config_structure: {
      base: 'configs/base.config',
      profiles: cache.profiles,
    },
    params: cache.paramsInfo,
  };
}

function handleGetWorkflowDetails(args: { workflow: string }): WorkflowDetails {
  const cache = getCache();
  const wf = cache.workflows.get(args.workflow);
  if (!wf) throw new McpError(ErrorCode.InvalidParams, `Workflow "${args.workflow}" not found`);

  const dag = buildDag(wf, cache.modules, REPO_ROOT);
  const { channels } = analyzeChannels(wf);

  const moduleConnections = wf.main
    .filter(s => s.type === 'call' && s.process)
    .map(s => ({
      module: s.process!,
      input_channels: s.inputs || [],
      output_channels: wf.main
        .filter(a => a.type === 'assign' && a.process === s.process)
        .map(a => a.target || ''),
    }));

  return {
    name: args.workflow,
    entrypoint: `${args.workflow}.nf`,
    dag,
    channels,
    module_connections: moduleConnections,
  };
}

function handleGetDag(): Dag {
  const cache = getCache();
  // Build combined DAG from all workflows
  const allNodes: Dag['nodes'] = [];
  const allEdges: Dag['edges'] = [];
  const allBranches: Dag['branches'] = [];
  const allCollectPoints: string[] = [];
  const allFanIn: Dag['fan_in_points'] = [];
  const allFanOut: Dag['fan_out_points'] = [];
  const allGpuNodes: string[] = [];

  for (const [name, wf] of cache.workflows) {
    const dag = buildDag(wf, cache.modules, REPO_ROOT);
    allNodes.push(...dag.nodes);
    allEdges.push(...dag.edges);
    allBranches.push(...dag.branches);
    allCollectPoints.push(...dag.collect_points);
    allFanIn.push(...dag.fan_in_points);
    allFanOut.push(...dag.fan_out_points);
    allGpuNodes.push(...dag.gpu_nodes);
  }

  return {
    nodes: allNodes,
    edges: allEdges,
    branches: allBranches,
    collect_points: [...new Set(allCollectPoints)],
    fan_in_points: allFanIn,
    fan_out_points: allFanOut,
    gpu_nodes: [...new Set(allGpuNodes)],
  };
}

function handleSuggestPipeline(args: { goal: string; constraints?: { profile?: string; no_gpu?: boolean } }): PipelineSuggestion {
  const cache = getCache();
  return suggestPipeline(args.goal, args.constraints || {}, cache.moduleInfos);
}

function handleComposeWorkflow(args: ComposeRequest): ComposeResult {
  const cache = getCache();
  return composeWorkflow(args, cache.moduleInfos, REPO_ROOT);
}

function handleValidateWorkflow(args: { workflow: string; profile: string; params?: Record<string, string> }): ValidationResult {
  const cache = getCache();
  return validateWorkflow(
    args.workflow,
    args.profile,
    args.params || {},
    cache.paramsInfo,
    cache.profiles,
    cache.moduleInfos,
  );
}

async function handleRunWorkflow(args: RunRequest): Promise<RunResult> {
  return runWorkflow(args, REPO_ROOT);
}

async function handleResumeRun(args: { run_id: string; profile: string }): Promise<RunResult> {
  return resumeRun(args.run_id, args.profile, REPO_ROOT);
}

function handleAnalyzeSamplesheet(args: { file_path: string }): SamplesheetAnalysis {
  const filePath = path.isAbsolute(args.file_path)
    ? args.file_path
    : path.join(REPO_ROOT, args.file_path);
  return analyzeSamplesheet(filePath);
}

function handleSuggestParams(args: { workflow: string; samplesheet_path?: string; params?: Record<string, string> }): ParamSuggestion {
  const cache = getCache();

  let samplesheetAnalysis: SamplesheetAnalysis = {
    valid: true,
    row_count: 0,
    required_fields_present: [],
    required_fields_missing: [],
    species_detected: [],
    species_mix: false,
    needs_harmonization: false,
    warnings: [],
    errors: [],
  };

  if (args.samplesheet_path) {
    const filePath = path.isAbsolute(args.samplesheet_path)
      ? args.samplesheet_path
      : path.join(REPO_ROOT, args.samplesheet_path);
    samplesheetAnalysis = analyzeSamplesheet(filePath);
  }

  return suggestParams(args.workflow, samplesheetAnalysis, args.params || {});
}

// ---------------------------------------------------------------------------
// Server setup
// ---------------------------------------------------------------------------

const server = new Server(
  {
    name: 'nextflow-workflows-server',
    version: '0.1.0',
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: 'discover_repository',
      description: 'Scan the GoodWorkflows DSL2 Nextflow repository and return a structured representation of workflows, modules, configs, profiles, and parameters.',
      inputSchema: {
        type: 'object',
        properties: {},
        required: [],
      },
    },
    {
      name: 'get_workflow_details',
      description: 'Get detailed information about a specific workflow including its full DAG, channel structure, and module-level connections.',
      inputSchema: {
        type: 'object',
        properties: {
          workflow: {
            type: 'string',
            description: 'Name of the workflow (e.g., "integration", "ingest_export", "ingest_tabulate")',
          },
        },
        required: ['workflow'],
      },
    },
    {
      name: 'get_dag',
      description: 'Get the full Directed Acyclic Graph (DAG) of all workflows with nodes, edges, branches, .collect() boundaries, fan-in/fan-out patterns, and GPU-labeled nodes.',
      inputSchema: {
        type: 'object',
        properties: {},
        required: [],
      },
    },
    {
      name: 'suggest_pipeline',
      description: 'Given a goal and constraints, suggest a pipeline composition using existing modules. Respects labels, resource classes, and the dual-branch design.',
      inputSchema: {
        type: 'object',
        properties: {
          goal: {
            type: 'string',
            description: 'Description of what you want to accomplish (e.g., "cross-species integration without GPU")',
          },
          constraints: {
            type: 'object',
            properties: {
              profile: { type: 'string', description: 'Target execution profile' },
              no_gpu: { type: 'boolean', description: 'Exclude GPU-dependent modules' },
            },
          },
        },
        required: ['goal'],
      },
    },
    {
      name: 'compose_workflow',
      description: 'Generate a new valid DSL2 workflow file from a list of existing modules. Handles correct channel wiring, .collect() placement, stub compatibility, and channel type validation.',
      inputSchema: {
        type: 'object',
        properties: {
          name: { type: 'string', description: 'Name for the new workflow' },
          modules: {
            type: 'array',
            items: { type: 'string' },
            description: 'List of module names to include in order',
          },
          with_tabulate: {
            type: 'boolean',
            description: 'Include the independent TABULATE metadata branch',
          },
        },
        required: ['name', 'modules'],
      },
    },
    {
      name: 'validate_workflow',
      description: 'Validate a workflow for execution readiness. Checks required params, profile compatibility, GPU constraints, and config inheritance.',
      inputSchema: {
        type: 'object',
        properties: {
          workflow: { type: 'string', description: 'Workflow name to validate' },
          profile: { type: 'string', description: 'Target execution profile' },
          params: {
            type: 'object',
            description: 'Parameters to validate against',
          },
        },
        required: ['workflow', 'profile'],
      },
    },
    {
      name: 'run_workflow',
      description: 'Execute a Nextflow workflow using the Nextflow CLI internally. On Windows, wraps via WSL. Returns structured results (run_id, logs path, status) — never exposes raw shell commands.',
      inputSchema: {
        type: 'object',
        properties: {
          workflow: { type: 'string', description: 'Workflow name to run' },
          profile: { type: 'string', description: 'Execution profile (local, slurm_singularity, test)' },
          params: {
            type: 'object',
            description: 'Workflow parameters',
          },
        },
        required: ['workflow', 'profile'],
      },
    },
    {
      name: 'resume_run',
      description: 'Resume a previous Nextflow run using -resume.',
      inputSchema: {
        type: 'object',
        properties: {
          run_id: { type: 'string', description: 'Run ID to resume' },
          profile: { type: 'string', description: 'Execution profile' },
        },
        required: ['run_id', 'profile'],
      },
    },
    {
      name: 'analyze_samplesheet',
      description: 'Analyze a samplesheet CSV file. Validates required fields (id, species, and either output_file_id or url), detects species mix, and warns if harmonization is needed.',
      inputSchema: {
        type: 'object',
        properties: {
          file_path: { type: 'string', description: 'Path to the samplesheet CSV file (absolute or relative to repo root)' },
        },
        required: ['file_path'],
      },
    },
    {
      name: 'suggest_params',
      description: 'Suggest Nextflow parameters (--export_assay, scMODAL params, tabulate columns) based on the selected workflow and input data context.',
      inputSchema: {
        type: 'object',
        properties: {
          workflow: { type: 'string', description: 'Workflow name' },
          samplesheet_path: { type: 'string', description: 'Path to samplesheet for context-aware suggestions' },
          params: { type: 'object', description: 'Existing params to avoid re-suggesting' },
        },
        required: ['workflow'],
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    switch (name) {
      case 'discover_repository':
        return { content: [{ type: 'text', text: JSON.stringify(handleDiscoverRepository(), null, 2) }] };

      case 'get_workflow_details':
        return { content: [{ type: 'text', text: JSON.stringify(handleGetWorkflowDetails(args as { workflow: string }), null, 2) }] };

      case 'get_dag':
        return { content: [{ type: 'text', text: JSON.stringify(handleGetDag(), null, 2) }] };

      case 'suggest_pipeline':
        return { content: [{ type: 'text', text: JSON.stringify(handleSuggestPipeline(args as { goal: string; constraints?: { profile?: string; no_gpu?: boolean } }), null, 2) }] };

      case 'compose_workflow':
        return { content: [{ type: 'text', text: JSON.stringify(handleComposeWorkflow(args as unknown as ComposeRequest), null, 2) }] };

      case 'validate_workflow':
        return { content: [{ type: 'text', text: JSON.stringify(handleValidateWorkflow(args as { workflow: string; profile: string; params?: Record<string, string> }), null, 2) }] };

      case 'run_workflow': {
        const result = await handleRunWorkflow(args as unknown as RunRequest);
        return { content: [{ type: 'text', text: JSON.stringify(result, null, 2) }] };
      }

      case 'resume_run': {
        const result = await handleResumeRun(args as { run_id: string; profile: string });
        return { content: [{ type: 'text', text: JSON.stringify(result, null, 2) }] };
      }

      case 'analyze_samplesheet':
        return { content: [{ type: 'text', text: JSON.stringify(handleAnalyzeSamplesheet(args as { file_path: string }), null, 2) }] };

      case 'suggest_params':
        return { content: [{ type: 'text', text: JSON.stringify(handleSuggestParams(args as { workflow: string; samplesheet_path?: string; params?: Record<string, string> }), null, 2) }] };

      default:
        throw new McpError(ErrorCode.MethodNotFound, `Unknown tool: ${name}`);
    }
  } catch (error) {
    if (error instanceof McpError) throw error;
    return {
      content: [{ type: 'text', text: `Error: ${(error as Error).message}` }],
      isError: true,
    };
  }
});

// Error handling
server.onerror = (error) => console.error('[MCP Error]', error);
process.on('SIGINT', async () => {
  await server.close();
  process.exit(0);
});

// Start server
const transport = new StdioServerTransport();
server.connect(transport).then(() => {
  console.error('Nextflow Workflows MCP server running on stdio');
  console.error(`Repository root: ${REPO_ROOT}`);
}).catch(console.error);