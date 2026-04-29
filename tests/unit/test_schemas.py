"""
Schema validation tests for all MCP tool outputs.

Every tool output must conform to its JSON Schema definition.
These tests validate the schema validator itself and ensure
all output types are correctly defined.
"""

import pytest

# Import from helpers
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from helpers.schema_validator import (
    validate_tool_output,
    TOOL_SCHEMAS,
    REPOSITORY_DISCOVERY_SCHEMA,
    DAG_SCHEMA,
    WORKFLOW_DETAILS_SCHEMA,
    PIPELINE_SUGGESTION_SCHEMA,
    COMPOSE_RESULT_SCHEMA,
    VALIDATION_RESULT_SCHEMA,
    RUN_RESULT_SCHEMA,
    SAMPLESHEET_ANALYSIS_SCHEMA,
    PARAM_SUGGESTION_SCHEMA,
)


class TestSchemaDefinitions:
    """Verify all schemas are well-formed and cover all tools."""

    def test_all_tools_have_schemas(self):
        """Every tool in TOOL_SCHEMAS has a valid schema."""
        expected_tools = [
            "discover_repository",
            "get_workflow_details",
            "get_dag",
            "suggest_pipeline",
            "compose_workflow",
            "validate_workflow",
            "run_workflow",
            "resume_run",
            "analyze_samplesheet",
            "suggest_params",
        ]
        for tool in expected_tools:
            assert tool in TOOL_SCHEMAS, f"Missing schema for tool: {tool}"

    def test_all_schemas_have_type_object(self):
        """All top-level schemas should be type 'object'."""
        for tool_name, schema in TOOL_SCHEMAS.items():
            assert schema.get("type") == "object", (
                f"Schema for '{tool_name}' is not type 'object'"
            )

    def test_all_schemas_have_required_fields(self):
        """All schemas should define required fields."""
        for tool_name, schema in TOOL_SCHEMAS.items():
            assert "required" in schema, (
                f"Schema for '{tool_name}' missing 'required' field"
            )
            assert isinstance(schema["required"], list), (
                f"Schema for '{tool_name}' 'required' is not a list"
            )


class TestRepositoryDiscoverySchema:
    """Validate RepositoryDiscovery output schema."""

    def test_valid_discovery_passes(self):
        """A valid discovery output should pass validation."""
        valid_output = {
            "workflows": [
                {
                    "name": "integration",
                    "entrypoint": "integration.nf",
                    "stages": ["INGEST", "EXPORT_COUNTS"],
                    "type": "mixed",
                    "uses_modules": ["INGEST", "EXPORT_COUNTS"],
                }
            ],
            "modules": [
                {
                    "name": "INGEST",
                    "path": "modules/local/rdiscvr/ingest/main.nf",
                    "inputs": ["meta"],
                    "outputs": ["rds"],
                    "label": "process_ingest",
                    "has_stub": True,
                    "is_gpu": False,
                }
            ],
            "profiles": ["test", "local"],
            "config_structure": {
                "base": "configs/base.config",
                "profiles": [
                    {
                        "name": "test",
                        "config_file": "configs/test.config",
                        "description": "CI test profile",
                        "is_active": True,
                    }
                ],
            },
            "params": {
                "required": ["input"],
                "optional": ["outdir"],
                "defaults": {"outdir": "./outputs"},
            },
        }
        errors = validate_tool_output("discover_repository", valid_output)
        assert len(errors) == 0, f"Unexpected errors: {errors}"

    def test_missing_required_field_fails(self):
        """Missing a required field should produce an error."""
        invalid_output = {
            "workflows": [],
            # missing "modules"
            "profiles": [],
            "config_structure": {"base": "", "profiles": []},
            "params": {"required": [], "optional": [], "defaults": {}},
        }
        errors = validate_tool_output("discover_repository", invalid_output)
        assert len(errors) > 0
        assert any("modules" in e for e in errors)

    def test_wrong_type_fails(self):
        """Wrong type for a field should produce an error."""
        invalid_output = {
            "workflows": "not_an_array",  # should be array
            "modules": [],
            "profiles": [],
            "config_structure": {"base": "", "profiles": []},
            "params": {"required": [], "optional": [], "defaults": {}},
        }
        errors = validate_tool_output("discover_repository", invalid_output)
        assert len(errors) > 0

    def test_invalid_workflow_type_fails(self):
        """Workflow type must be one of gpu/cpu/mixed."""
        invalid_output = {
            "workflows": [
                {
                    "name": "test",
                    "entrypoint": "test.nf",
                    "stages": [],
                    "type": "invalid_type",  # not in enum
                    "uses_modules": [],
                }
            ],
            "modules": [],
            "profiles": [],
            "config_structure": {"base": "", "profiles": []},
            "params": {"required": [], "optional": [], "defaults": {}},
        }
        errors = validate_tool_output("discover_repository", invalid_output)
        assert len(errors) > 0


class TestDagSchema:
    """Validate DAG output schema."""

    def test_valid_dag_passes(self):
        """A valid DAG output should pass validation."""
        valid_dag = {
            "nodes": [
                {"id": "INGEST", "type": "process", "is_gpu": False},
                {"id": "collect:ch1", "type": "collect"},
            ],
            "edges": [
                {"from": "INGEST", "to": "EXPORT_COUNTS"},
            ],
            "branches": [
                {"name": "metadata", "nodes": ["INGEST_METADATA", "TABULATE"]},
            ],
            "collect_points": ["ch1"],
            "fan_in_points": [{"node": "GENE_HARMONIZE", "sources": ["EXPORT_COUNTS"]}],
            "fan_out_points": [],
            "gpu_nodes": ["SCMODAL_INTEGRATE"],
        }
        errors = validate_tool_output("get_dag", valid_dag)
        assert len(errors) == 0, f"Unexpected errors: {errors}"

    def test_missing_nodes_fails(self):
        """DAG without nodes should fail."""
        invalid_dag = {
            # missing "nodes"
            "edges": [],
            "branches": [],
            "collect_points": [],
            "fan_in_points": [],
            "fan_out_points": [],
            "gpu_nodes": [],
        }
        errors = validate_tool_output("get_dag", invalid_dag)
        assert len(errors) > 0

    def test_invalid_node_type_fails(self):
        """Node type must be one of process/collect/map/channel."""
        invalid_dag = {
            "nodes": [{"id": "X", "type": "invalid"}],
            "edges": [],
            "branches": [],
            "collect_points": [],
            "fan_in_points": [],
            "fan_out_points": [],
            "gpu_nodes": [],
        }
        errors = validate_tool_output("get_dag", invalid_dag)
        assert len(errors) > 0


class TestValidationResultSchema:
    """Validate ValidationResult output schema."""

    def test_valid_validation_passes(self):
        """A valid validation result should pass."""
        valid = {
            "valid": True,
            "errors": [],
            "warnings": [],
            "missing_params": [],
            "gpu_conflicts": [],
            "profile_issues": [],
        }
        errors = validate_tool_output("validate_workflow", valid)
        assert len(errors) == 0, f"Unexpected errors: {errors}"

    def test_invalid_validation_with_errors(self):
        """A validation result with errors should still pass schema."""
        result = {
            "valid": False,
            "errors": ["Missing required param: input"],
            "warnings": ["GPU module with local profile"],
            "missing_params": ["input"],
            "gpu_conflicts": ["SCMODAL_INTEGRATE"],
            "profile_issues": [],
        }
        errors = validate_tool_output("validate_workflow", result)
        assert len(errors) == 0, f"Unexpected errors: {errors}"


class TestSamplesheetAnalysisSchema:
    """Validate SamplesheetAnalysis output schema."""

    def test_valid_analysis_passes(self):
        """A valid samplesheet analysis should pass."""
        valid = {
            "valid": True,
            "row_count": 3,
            "required_fields_present": ["id", "output_file_id", "species"],
            "required_fields_missing": [],
            "species_detected": ["human", "macaque", "mouse"],
            "species_mix": True,
            "needs_harmonization": True,
            "warnings": ["Multiple species detected"],
            "errors": [],
        }
        errors = validate_tool_output("analyze_samplesheet", valid)
        assert len(errors) == 0, f"Unexpected errors: {errors}"

    def test_invalid_analysis_with_errors(self):
        """Analysis with errors should still pass schema."""
        result = {
            "valid": False,
            "row_count": 0,
            "required_fields_present": [],
            "required_fields_missing": ["id", "output_file_id", "species"],
            "species_detected": [],
            "species_mix": False,
            "needs_harmonization": False,
            "warnings": [],
            "errors": ["File not found"],
        }
        errors = validate_tool_output("analyze_samplesheet", result)
        assert len(errors) == 0, f"Unexpected errors: {errors}"


class TestComposeResultSchema:
    """Validate ComposeResult output schema."""

    def test_valid_compose_passes(self):
        """A valid compose result should pass."""
        valid = {
            "workflow_name": "test_workflow",
            "workflow_content": "#!/usr/bin/env nextflow\nworkflow TEST {}",
            "warnings": [],
        }
        errors = validate_tool_output("compose_workflow", valid)
        assert len(errors) == 0, f"Unexpected errors: {errors}"


class TestRunResultSchema:
    """Validate RunResult output schema."""

    def test_valid_run_result_passes(self):
        """A valid run result should pass."""
        valid = {
            "run_id": "run_12345",
            "logs_path": "/path/to/logs",
            "status": "completed",
            "exit_code": 0,
        }
        errors = validate_tool_output("run_workflow", valid)
        assert len(errors) == 0, f"Unexpected errors: {errors}"

    def test_invalid_status_fails(self):
        """Status must be one of running/completed/failed."""
        invalid = {
            "run_id": "run_12345",
            "logs_path": "/path/to/logs",
            "status": "unknown_status",
        }
        errors = validate_tool_output("run_workflow", invalid)
        assert len(errors) > 0


class TestParamSuggestionSchema:
    """Validate ParamSuggestion output schema."""

    def test_valid_suggestion_passes(self):
        """A valid param suggestion should pass."""
        valid = {
            "export_assay": "RNA",
            "scmodal_params": {"latent": 20},
            "tabulate_columns": ["col1", "col2"],
            "notes": ["Defaulting export_assay to RNA"],
        }
        errors = validate_tool_output("suggest_params", valid)
        assert len(errors) == 0, f"Unexpected errors: {errors}"

    def test_minimal_suggestion_passes(self):
        """Minimal suggestion with only notes should pass."""
        minimal = {
            "notes": [],
        }
        errors = validate_tool_output("suggest_params", minimal)
        assert len(errors) == 0, f"Unexpected errors: {errors}"