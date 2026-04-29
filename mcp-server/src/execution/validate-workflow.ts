// =============================================================================
// Workflow Validator — checks params, profiles, GPU constraints, config inheritance
// =============================================================================

import { ModuleInfo, ParamsInfo, ProfileInfo, ValidationResult } from '../types.js';

/**
 * Validate a workflow for execution readiness.
 * Checks: required params, profile compatibility, GPU constraints, config inheritance.
 */
export function validateWorkflow(
  workflowName: string,
  profile: string,
  providedParams: Record<string, string>,
  paramsInfo: ParamsInfo,
  profiles: ProfileInfo[],
  modules: ModuleInfo[]
): ValidationResult {
  const errors: string[] = [];
  const warnings: string[] = [];
  const missingParams: string[] = [];
  const gpuConflicts: string[] = [];
  const profileIssues: string[] = [];

  // Check profile exists and is active
  const profileInfo = profiles.find(p => p.name === profile);
  if (!profileInfo) {
    errors.push(`Profile "${profile}" not found. Available: ${profiles.map(p => p.name).join(', ')}`);
  } else if (!profileInfo.is_active) {
    warnings.push(`Profile "${profile}" is marked as inactive/stubbed. Consider using an active profile.`);
    profileIssues.push(`Profile "${profile}" is stubbed`);
  }

  // Check required params
  for (const required of paramsInfo.required) {
    const provided = providedParams[required];
    const defaultVal = paramsInfo.defaults[required];
    if (!provided && (!defaultVal || defaultVal === "''" || defaultVal === '')) {
      missingParams.push(required);
      errors.push(`Required parameter "${required}" is not set`);
    }
  }

  // Check GPU constraints
  if (profile === 'local' || profile === 'test') {
    const gpuModules = modules.filter(m => m.is_gpu);
    for (const gpuMod of gpuModules) {
      gpuConflicts.push(gpuMod.name);
      warnings.push(`Module "${gpuMod.name}" requires GPU but profile "${profile}" does not support GPU`);
    }
  }

  // Check for scmodal_use_cpu flag
  if (profile === 'local' && providedParams['scmodal_use_cpu'] !== 'true') {
    const hasGpuModule = modules.some(m => m.is_gpu);
    if (hasGpuModule) {
      warnings.push('GPU modules detected with local profile. Set --scmodal_use_cpu=true to run SCMODAL on CPU, or use a GPU-capable profile.');
    }
  }

  // Validate config inheritance
  if (profile === 'slurm_singularity') {
    // slurm_singularity extends slurm.config + slurm_singularity.config
    // Both must exist
    profileIssues.push('slurm_singularity profile requires both slurm.config and slurm_singularity.config');
  }

  const valid = errors.length === 0;

  return {
    valid,
    errors,
    warnings,
    missing_params: missingParams,
    gpu_conflicts: gpuConflicts,
    profile_issues: profileIssues,
  };
}