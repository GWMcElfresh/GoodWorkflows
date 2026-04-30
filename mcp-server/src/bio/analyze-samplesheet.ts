// =============================================================================
// Samplesheet Analyzer — validates samplesheet fields, detects species mix
// =============================================================================

import * as fs from 'fs';
import { SamplesheetAnalysis, SamplesheetRow } from '../types.js';

/**
 * Analyze a samplesheet CSV file.
 * Validates required fields: id, species, and either output_file_id or url.
 * Detects species mix and warns if harmonization is needed.
 */
export function analyzeSamplesheet(filePath: string): SamplesheetAnalysis {
  const errors: string[] = [];
  const warnings: string[] = [];

  if (!fs.existsSync(filePath)) {
    return {
      valid: false,
      row_count: 0,
      required_fields_present: [],
      required_fields_missing: ['id', 'species', 'output_file_id or url'],
      species_detected: [],
      species_mix: false,
      needs_harmonization: false,
      warnings: [],
      errors: [`File not found: ${filePath}`],
    };
  }

  const content = fs.readFileSync(filePath, 'utf-8');
  const lines = content.split('\n').filter(line => line.trim().length > 0);

  if (lines.length < 2) {
    return {
      valid: false,
      row_count: 0,
      required_fields_present: [],
      required_fields_missing: ['id', 'species', 'output_file_id or url'],
      species_detected: [],
      species_mix: false,
      needs_harmonization: false,
      warnings: [],
      errors: ['Samplesheet is empty or has no data rows'],
    };
  }

  // Parse header
  const header = lines[0].split(',').map(h => h.trim());
  const requiredFields = ['id', 'species'];
  const requiredFieldsPresent = requiredFields.filter(f => header.includes(f));
  const requiredFieldsMissing = requiredFields.filter(f => !header.includes(f));

  // Check for data source column: either output_file_id or url
  const hasOutputFileId = header.includes('output_file_id');
  const hasUrl = header.includes('url');
  if (hasOutputFileId) {
    requiredFieldsPresent.push('output_file_id');
  }
  if (hasUrl) {
    requiredFieldsPresent.push('url');
  }
  if (!hasOutputFileId && !hasUrl) {
    requiredFieldsMissing.push('output_file_id or url');
  }

  if (requiredFieldsMissing.length > 0) {
    errors.push(`Missing required columns: ${requiredFieldsMissing.join(', ')}`);
  }

  // Parse data rows
  const rows: SamplesheetRow[] = [];
  for (let i = 1; i < lines.length; i++) {
    const values = lines[i].split(',').map(v => v.trim());
    const row: Record<string, string | undefined> = {};
    for (let j = 0; j < header.length; j++) {
      row[header[j]] = values[j] || '';
    }
    rows.push(row as unknown as SamplesheetRow);
  }

  // Validate each row has required fields
  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];
    if (!row.id) {
      errors.push(`Row ${i + 2}: missing "id"`);
    }
    if (!row.species) {
      errors.push(`Row ${i + 2}: missing "species"`);
    }
    // Must have at least one data source
    if (!row.output_file_id && !row.url) {
      errors.push(`Row ${i + 2}: missing both "output_file_id" and "url" — must provide one`);
    }
  }

  // Detect species
  const speciesSet = new Set<string>();
  for (const row of rows) {
    if (row.species) {
      speciesSet.add(row.species.toLowerCase());
    }
  }
  const speciesDetected = Array.from(speciesSet);
  const speciesMix = speciesDetected.length > 1;
  const needsHarmonization = speciesMix;

  if (speciesMix) {
    warnings.push(`Multiple species detected: ${speciesDetected.join(', ')}. Gene harmonization is recommended.`);
  }

  // Check for common issues
  const sampleIds = rows.map(r => r.id);
  const uniqueIds = new Set(sampleIds);
  if (uniqueIds.size !== sampleIds.length) {
    warnings.push('Duplicate sample IDs detected');
  }

  const valid = errors.length === 0;

  return {
    valid,
    row_count: rows.length,
    required_fields_present: requiredFieldsPresent,
    required_fields_missing: requiredFieldsMissing,
    species_detected: speciesDetected,
    species_mix: speciesMix,
    needs_harmonization: needsHarmonization,
    warnings,
    errors,
  };
}