// =============================================================================
// DSL2 Module Parser — parses process blocks in module main.nf files
// =============================================================================

import * as fs from 'fs';
import * as path from 'path';
import { ParsedProcess } from '../types.js';

/**
 * Parse a DSL2 process definition from a module main.nf file.
 * Extracts: process name, label, container, input/output channels, stub presence, GPU detection.
 */
export function parseProcessFile(filePath: string): ParsedProcess {
  const content = fs.readFileSync(filePath, 'utf-8');
  const lines = content.split('\n');

  let name = '';
  let label: string | undefined;
  let container: string | undefined;
  let publishDir: string | undefined;
  const inputs: { name: string; type: string }[] = [];
  const outputs: { name: string; type: string; emit?: string }[] = [];
  let hasStub = false;
  let isGpu = false;

  let inProcess = false;
  let inInput = false;
  let inOutput = false;
  let inStub = false;
  let braceDepth = 0;

  for (const line of lines) {
    const trimmed = line.trim();

    // Detect process start
    const procMatch = trimmed.match(/^process\s+(\w+)\s*\{/);
    if (procMatch) {
      name = procMatch[1];
      inProcess = true;
      braceDepth = 1;
      continue;
    }

    if (!inProcess) continue;

    // Track braces
    const openBraces = (trimmed.match(/\{/g) || []).length;
    const closeBraces = (trimmed.match(/\}/g) || []).length;
    braceDepth += openBraces - closeBraces;

    if (braceDepth <= 0) {
      inProcess = false;
      inInput = false;
      inOutput = false;
      inStub = false;
      break;
    }

    // Detect sections
    if (trimmed.startsWith('input:')) {
      inInput = true;
      inOutput = false;
      inStub = false;
      continue;
    }
    if (trimmed.startsWith('output:')) {
      inInput = false;
      inOutput = true;
      inStub = false;
      continue;
    }
    if (trimmed.startsWith('stub:') || trimmed.startsWith('stub')) {
      inInput = false;
      inOutput = false;
      inStub = true;
      hasStub = true;
      continue;
    }
    if (trimmed.startsWith('when:') || trimmed.startsWith('exec:') || trimmed.startsWith('script:') || trimmed.startsWith('shell:')) {
      inInput = false;
      inOutput = false;
      inStub = false;
      continue;
    }

    // Parse directives
    const labelMatch = trimmed.match(/^label\s+['"]([^'"]+)['"]/);
    if (labelMatch) {
      label = labelMatch[1];
      if (labelMatch[1].includes('gpu')) isGpu = true;
    }

    const containerMatch = trimmed.match(/^container\s+['"]([^'"]+)['"]/);
    if (containerMatch) {
      container = containerMatch[1];
    }

    const publishDirMatch = trimmed.match(/^publishDir\s+['"]([^'"]+)['"]/);
    if (publishDirMatch) {
      publishDir = publishDirMatch[1];
    }

    // GPU detection from container name
    if (container && (container.includes('cuda') || container.includes('gpu'))) {
      isGpu = true;
    }

    // Parse input channels
    if (inInput) {
      // tuple val(meta), path(input_file)
      const tupleMatch = trimmed.match(/tuple\s+val\((\w+)\)\s*,\s*path\((\w+)\)/);
      if (tupleMatch) {
        inputs.push({ name: tupleMatch[1], type: 'val' });
        inputs.push({ name: tupleMatch[2], type: 'path' });
      }

      // path(input_file)
      const pathMatch = trimmed.match(/path\((\w+)\)/);
      if (pathMatch && !tupleMatch) {
        inputs.push({ name: pathMatch[1], type: 'path' });
      }

      // val(variable)
      const valMatch = trimmed.match(/val\((\w+)\)/);
      if (valMatch && !tupleMatch) {
        inputs.push({ name: valMatch[1], type: 'val' });
      }
    }

    // Parse output channels
    if (inOutput) {
      // tuple val(meta), path("*.rds"), emit: rds
      const tupleEmitMatch = trimmed.match(/tuple\s+val\((\w+)\)\s*,\s*path\(["']?([^"',]+)["']?\)\s*,\s*emit:\s*(\w+)/);
      if (tupleEmitMatch) {
        outputs.push({ name: tupleEmitMatch[2], type: 'path', emit: tupleEmitMatch[3] });
      }

      // path("*.csv"), emit: metadata_csv
      const pathEmitMatch = trimmed.match(/path\(["']?([^"',]+)["']?\)\s*,\s*emit:\s*(\w+)/);
      if (pathEmitMatch) {
        outputs.push({ name: pathEmitMatch[1], type: 'path', emit: pathEmitMatch[2] });
      }

      // path("*.rds")
      const pathOnlyMatch = trimmed.match(/path\(["']?([^"',]+)["']?\)/);
      if (pathOnlyMatch && !pathEmitMatch && !tupleEmitMatch) {
        outputs.push({ name: pathOnlyMatch[1], type: 'path' });
      }
    }
  }

  return { name, label, container, publish_dir: publishDir, inputs, outputs, has_stub: hasStub, is_gpu: isGpu, raw_body: content };
}

/**
 * Discover all module directories under modules/local/
 */
export function discoverModuleDirs(repoRoot: string): string[] {
  const modulesDir = path.join(repoRoot, 'modules', 'local');
  if (!fs.existsSync(modulesDir)) return [];

  const dirs: string[] = [];

  function walk(dir: string) {
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    for (const entry of entries) {
      if (entry.isDirectory()) {
        const fullPath = path.join(dir, entry.name);
        // Check if this directory has a main.nf
        if (fs.existsSync(path.join(fullPath, 'main.nf'))) {
          dirs.push(fullPath);
        } else {
          walk(fullPath);
        }
      }
    }
  }

  walk(modulesDir);
  return dirs;
}

/**
 * Get the module name from its directory path.
 * e.g., modules/local/rdiscvr/ingest → INGEST
 */
export function moduleNameFromPath(modulePath: string): string {
  const parts = modulePath.split(path.sep);
  const lastDir = parts[parts.length - 1];
  return lastDir.toUpperCase();
}