// =============================================================================
// Shared TypeScript interfaces for the nextflow_workflows MCP server
// =============================================================================

// --- Repository Discovery ---

export interface WorkflowInfo {
  name: string;
  entrypoint: string;
  stages: string[];
  type: 'gpu' | 'cpu' | 'mixed';
  uses_modules: string[];
  description?: string;
}

export interface ModuleInfo {
  name: string;
  path: string;
  inputs: string[];
  outputs: string[];
  label: string;
  has_stub: boolean;
  container?: string;
  is_gpu: boolean;
  publish_dir?: string;
}

export interface ConfigStructure {
  base: string;
  profiles: ProfileInfo[];
}

export interface ProfileInfo {
  name: string;
  config_file: string;
  description: string;
  is_active: boolean; // slurm is stubbed
}

export interface ParamsInfo {
  required: string[];
  optional: string[];
  defaults: Record<string, string>;
}

export interface RepositoryDiscovery {
  workflows: WorkflowInfo[];
  modules: ModuleInfo[];
  profiles: string[];
  config_structure: ConfigStructure;
  params: ParamsInfo;
}

// --- DAG ---

export interface DagNode {
  id: string;
  type: 'process' | 'collect' | 'map' | 'channel';
  label?: string;
  is_gpu?: boolean;
  module_path?: string;
}

export interface DagEdge {
  from: string;
  to: string;
  channel_type?: string;
  is_collect?: boolean;
}

export interface DagBranch {
  name: string;
  nodes: string[];
  description?: string;
}

export interface Dag {
  nodes: DagNode[];
  edges: DagEdge[];
  branches: DagBranch[];
  collect_points: string[];
  fan_in_points: { node: string; sources: string[] }[];
  fan_out_points: { node: string; targets: string[] }[];
  gpu_nodes: string[];
}

// --- Workflow Details ---

export interface ChannelStructure {
  name: string;
  type: string; // e.g. "tuple val(meta), path(rds)"
  source: string;
  targets: string[];
}

export interface WorkflowDetails {
  name: string;
  entrypoint: string;
  dag: Dag;
  channels: ChannelStructure[];
  module_connections: { module: string; input_channels: string[]; output_channels: string[] }[];
}

// --- Composition ---

export interface PipelineSuggestion {
  workflow_plan: string[];
  excluded: string[];
  reasoning: string;
  warnings?: string[];
}

export interface ComposeRequest {
  name: string;
  modules: string[];
  with_tabulate?: boolean;
}

export interface ComposeResult {
  workflow_name: string;
  workflow_content: string;
  warnings: string[];
}

// --- Execution ---

export interface ValidationResult {
  valid: boolean;
  errors: string[];
  warnings: string[];
  missing_params: string[];
  gpu_conflicts: string[];
  profile_issues: string[];
}

export interface RunRequest {
  workflow: string;
  profile: string;
  params: Record<string, string>;
}

export interface RunResult {
  run_id: string;
  logs_path: string;
  status: 'running' | 'completed' | 'failed';
  exit_code?: number;
  stdout_summary?: string;
}

// --- Bio ---

export interface SamplesheetRow {
  id: string;
  output_file_id: string;
  species: string;
  [key: string]: string;
}

export interface SamplesheetAnalysis {
  valid: boolean;
  row_count: number;
  required_fields_present: string[];
  required_fields_missing: string[];
  species_detected: string[];
  species_mix: boolean;
  needs_harmonization: boolean;
  warnings: string[];
  errors: string[];
}

export interface ParamSuggestion {
  export_assay?: string;
  scmodal_params?: Record<string, string | number>;
  tabulate_columns?: string[];
  tabulate_id_cols?: string[];
  notes: string[];
}

// --- Parsed DSL2 structures ---

export interface ParsedWorkflow {
  name: string;
  includes: { module_name: string; path: string }[];
  takes: { name: string; type: string }[];
  main: WorkflowStatement[];
  emits: { name: string; source: string }[];
}

export interface WorkflowStatement {
  type: 'call' | 'collect' | 'map' | 'assign' | 'branch';
  target?: string;
  process?: string;
  inputs?: string[];
  outputs?: string[];
  raw: string;
}

export interface ParsedProcess {
  name: string;
  label?: string;
  container?: string;
  publish_dir?: string;
  inputs: { name: string; type: string }[];
  outputs: { name: string; type: string; emit?: string }[];
  has_stub: boolean;
  is_gpu: boolean;
  raw_body: string;
}

export interface ParsedConfig {
  params: Record<string, string>;
  profiles: { name: string; includes: string[] }[];
  include_configs: string[];
  process_labels: Record<string, Record<string, string>>;
}