// =============================================================================
// Workflow Runner — executes Nextflow CLI internally, returns structured results
// =============================================================================

import { spawn } from 'child_process';
import * as path from 'path';
import * as os from 'os';
import { RunRequest, RunResult } from '../types.js';

/**
 * Execute a Nextflow workflow.
 * Uses Nextflow CLI internally. On Windows, wraps via WSL.
 * Returns structured results — never exposes raw shell commands.
 */
export async function runWorkflow(
  request: RunRequest,
  repoRoot: string
): Promise<RunResult> {
  const isWindows = os.platform() === 'win32';
  const runId = `run_${Date.now()}`;
  const logsPath = path.join(repoRoot, 'logs');

  // Build Nextflow command
  const nfArgs: string[] = [
    '-run',
    path.join(repoRoot, 'main.nf'),
    '-profile', request.profile,
    '--workflow', request.workflow,
  ];

  // Add user-provided params
  for (const [key, value] of Object.entries(request.params)) {
    nfArgs.push(`--${key}`, value);
  }

  // Add output directory
  nfArgs.push('--outdir', path.join(repoRoot, 'outputs', runId));

  return new Promise((resolve) => {
    let command: string;
    let args: string[];

    if (isWindows) {
      // Use WSL on Windows
      command = 'wsl';
      args = ['nextflow', ...nfArgs];
    } else {
      command = 'nextflow';
      args = nfArgs;
    }

    const child = spawn(command, args, {
      cwd: repoRoot,
      stdio: ['ignore', 'pipe', 'pipe'],
      env: { ...process.env },
    });

    let stdout = '';
    let stderr = '';

    child.stdout?.on('data', (data: Buffer) => {
      stdout += data.toString();
    });

    child.stderr?.on('data', (data: Buffer) => {
      stderr += data.toString();
    });

    child.on('close', (code: number | null) => {
      const exitCode = code ?? -1;
      const status: 'running' | 'completed' | 'failed' = exitCode === 0 ? 'completed' : 'failed';

      resolve({
        run_id: runId,
        logs_path: logsPath,
        status,
        exit_code: exitCode,
        stdout_summary: stdout.slice(-500), // Last 500 chars
      });
    });

    child.on('error', (err: Error) => {
      resolve({
        run_id: runId,
        logs_path: logsPath,
        status: 'failed',
        exit_code: -1,
        stdout_summary: `Error: ${err.message}`,
      });
    });
  });
}

/**
 * Resume a previous Nextflow run using -resume.
 */
export async function resumeRun(
  runId: string,
  profile: string,
  repoRoot: string
): Promise<RunResult> {
  const isWindows = os.platform() === 'win32';
  const logsPath = path.join(repoRoot, 'logs');

  const nfArgs: string[] = [
    '-run',
    path.join(repoRoot, 'main.nf'),
    '-profile', profile,
    '-resume', runId,
  ];

  return new Promise((resolve) => {
    let command: string;
    let args: string[];

    if (isWindows) {
      command = 'wsl';
      args = ['nextflow', ...nfArgs];
    } else {
      command = 'nextflow';
      args = nfArgs;
    }

    const child = spawn(command, args, {
      cwd: repoRoot,
      stdio: ['ignore', 'pipe', 'pipe'],
      env: { ...process.env },
    });

    let stdout = '';

    child.stdout?.on('data', (data: Buffer) => {
      stdout += data.toString();
    });

    child.on('close', (code: number | null) => {
      const exitCode = code ?? -1;
      const status: 'running' | 'completed' | 'failed' = exitCode === 0 ? 'completed' : 'failed';

      resolve({
        run_id: runId,
        logs_path: logsPath,
        status,
        exit_code: exitCode,
        stdout_summary: stdout.slice(-500),
      });
    });

    child.on('error', (err: Error) => {
      resolve({
        run_id: runId,
        logs_path: logsPath,
        status: 'failed',
        exit_code: -1,
        stdout_summary: `Error: ${err.message}`,
      });
    });
  });
}