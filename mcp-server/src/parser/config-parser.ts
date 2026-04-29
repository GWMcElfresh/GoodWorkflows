// =============================================================================
// DSL2 Config Parser — parses nextflow.config and profile config files
// =============================================================================

import * as fs from 'fs';
import * as path from 'path';
import { ParsedConfig, ProfileInfo, ParamsInfo } from '../types.js';

/**
 * Parse the main nextflow.config to extract profiles and config layering.
 */
export function parseNextflowConfig(repoRoot: string): ParsedConfig {
  const configPath = path.join(repoRoot, 'nextflow.config');
  if (!fs.existsSync(configPath)) {
    return { params: {}, profiles: [], include_configs: [], process_labels: {} };
  }

  const content = fs.readFileSync(configPath, 'utf-8');
  const params: Record<string, string> = {};
  const profiles: { name: string; includes: string[] }[] = [];
  const includeConfigs: string[] = [];

  // Extract includeConfig statements
  const includeMatches = content.matchAll(/includeConfig\s+['"]([^'"]+)['"]/g);
  for (const m of includeMatches) {
    includeConfigs.push(m[1]);
  }

  // Extract profile blocks
  const profileRegex = /(\w+)\s*\{([^}]*(?:\{[^}]*\}[^}]*)*)\}/g;
  let profileMatch;
  while ((profileMatch = profileRegex.exec(content)) !== null) {
    const profileName = profileMatch[1];
    const profileBody = profileMatch[2];
    const includes: string[] = [];

    const profileIncludeMatches = profileBody.matchAll(/includeConfig\s+['"]([^'"]+)['"]/g);
    for (const m of profileIncludeMatches) {
      includes.push(m[1]);
    }

    profiles.push({ name: profileName, includes });
  }

  return { params, profiles, include_configs: includeConfigs, process_labels: {} };
}

/**
 * Parse base.config to extract all default params.
 */
export function parseBaseConfig(repoRoot: string): ParamsInfo {
  const basePath = path.join(repoRoot, 'configs', 'base.config');
  if (!fs.existsSync(basePath)) {
    return { required: [], optional: [], defaults: {} };
  }

  const content = fs.readFileSync(basePath, 'utf-8');
  const defaults: Record<string, string> = {};
  const required: string[] = [];
  const optional: string[] = [];

  // Find params block
  const paramsMatch = content.match(/params\s*\{([^}]+)\}/s);
  if (paramsMatch) {
    const paramsBody = paramsMatch[1];
    const lines = paramsBody.split('\n');

    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('//') || trimmed.startsWith('/*')) continue;

      // param_name = 'value'
      const paramMatch = trimmed.match(/^(\w+)\s*=\s*(.+)$/);
      if (paramMatch) {
        const name = paramMatch[1];
        let value = paramMatch[2].trim();

        // Clean up the value
        value = value.replace(/^['"]/, '').replace(/['"]$/, '');
        value = value.replace(/^\/\//, '').trim();

        defaults[name] = value;

        // Identify required vs optional
        if (value === "''" || value === '""' || value === '' || value === 'false') {
          // Empty string defaults are likely required to be set
          if (['labkey_base_url', 'labkey_folder', 'input'].includes(name)) {
            required.push(name);
          } else {
            optional.push(name);
          }
        } else {
          optional.push(name);
        }
      }
    }
  }

  return { required, optional, defaults };
}

/**
 * Build profile info list from parsed configs.
 */
export function buildProfileInfo(repoRoot: string): ProfileInfo[] {
  const profiles: ProfileInfo[] = [
    {
      name: 'local',
      config_file: 'configs/local.config',
      description: 'Local macOS/Linux development with Podman',
      is_active: true,
    },
    {
      name: 'slurm',
      config_file: 'configs/slurm.config',
      description: 'HPC SLURM execution with Podman (effectively stubbed)',
      is_active: false,
    },
    {
      name: 'slurm_singularity',
      config_file: 'configs/slurm_singularity.config',
      description: 'HPC SLURM execution with Apptainer/Singularity',
      is_active: true,
    },
    {
      name: 'test',
      config_file: 'configs/test.config',
      description: 'CI smoke tests with stub runs, no containers',
      is_active: true,
    },
  ];

  return profiles;
}

/**
 * Parse a profile config file to extract process resource specs.
 */
export function parseProfileConfig(filePath: string): Record<string, Record<string, string>> {
  if (!fs.existsSync(filePath)) return {};

  const content = fs.readFileSync(filePath, 'utf-8');
  const processLabels: Record<string, Record<string, string>> = {};

  // Find withLabel blocks
  const withLabelRegex = /withLabel:\s*['"]([^'"]+)['"]\s*\{([^}]+)\}/g;
  let match;
  while ((match = withLabelRegex.exec(content)) !== null) {
    const label = match[1];
    const body = match[2];
    const specs: Record<string, string> = {};

    // Extract key-value pairs
    const kvMatches = body.matchAll(/(\w+)\s*=\s*['"]?([^'",\n]+)['"]?/g);
    for (const kv of kvMatches) {
      specs[kv[1]] = kv[2].trim();
    }

    processLabels[label] = specs;
  }

  return processLabels;
}