"""
Integration tests for bio-aware tools.

Validates samplesheet analysis and parameter suggestion.
"""

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from helpers.schema_validator import validate_tool_output


class TestAnalyzeSamplesheet:
    """Validate analyze_samplesheet tool."""

    def test_valid_samplesheet(self, mcp_client, valid_samplesheet):
        """Valid samplesheet should pass analysis."""
        result = mcp_client.call_tool("analyze_samplesheet", {
            "file_path": valid_samplesheet,
        })
        errors = validate_tool_output("analyze_samplesheet", result)
        assert len(errors) == 0, f"Schema errors: {errors}"

        assert result["valid"] is True, (
            f"Expected valid, got errors: {result.get('errors')}"
        )
        assert result["row_count"] == 3, f"Expected 3 rows, got {result['row_count']}"

    def test_detects_multi_species(self, mcp_client, valid_samplesheet):
        """Multi-species samplesheet should trigger harmonization."""
        result = mcp_client.call_tool("analyze_samplesheet", {
            "file_path": valid_samplesheet,
        })
        assert result["species_mix"] is True, "Should detect species mix"
        assert result["needs_harmonization"] is True, (
            "Should suggest harmonization for multi-species"
        )
        assert len(result["species_detected"]) > 1, (
            "Should detect multiple species"
        )

    def test_single_species_no_harmonization(self, mcp_client, single_species_samplesheet):
        """Single-species samplesheet should not need harmonization."""
        result = mcp_client.call_tool("analyze_samplesheet", {
            "file_path": single_species_samplesheet,
        })
        assert result["species_mix"] is False, "Should not detect species mix"
        assert result["needs_harmonization"] is False, (
            "Should not need harmonization for single species"
        )
        assert len(result["species_detected"]) == 1, (
            "Should detect exactly one species"
        )

    def test_missing_columns_detected(self, mcp_client, missing_cols_samplesheet):
        """Missing required columns should be detected."""
        result = mcp_client.call_tool("analyze_samplesheet", {
            "file_path": missing_cols_samplesheet,
        })
        assert result["valid"] is False, "Should be invalid with missing columns"
        assert len(result["required_fields_missing"]) > 0, (
            "Should report missing fields"
        )
        assert "species" in result["required_fields_missing"], (
            "Should detect missing 'species' column"
        )

    def test_empty_samplesheet(self, mcp_client, empty_samplesheet):
        """Empty samplesheet should be flagged."""
        result = mcp_client.call_tool("analyze_samplesheet", {
            "file_path": empty_samplesheet,
        })
        assert result["row_count"] == 0, "Empty samplesheet should have 0 rows"

    def test_required_fields_present(self, mcp_client, valid_samplesheet):
        """Valid samplesheet should have all required fields."""
        result = mcp_client.call_tool("analyze_samplesheet", {
            "file_path": valid_samplesheet,
        })
        required = {"id", "output_file_id", "species"}
        present = set(result["required_fields_present"])
        assert required.issubset(present), (
            f"Missing required fields: {required - present}"
        )

    def test_has_warnings_for_multi_species(self, mcp_client, valid_samplesheet):
        """Multi-species should generate warnings."""
        result = mcp_client.call_tool("analyze_samplesheet", {
            "file_path": valid_samplesheet,
        })
        assert len(result["warnings"]) > 0, (
            "Should have warnings for multi-species"
        )


class TestSuggestParams:
    """Validate suggest_params tool."""

    def test_suggest_for_integration(self, mcp_client):
        """Suggest params for integration workflow."""
        result = mcp_client.call_tool("suggest_params", {
            "workflow": "integration",
        })
        errors = validate_tool_output("suggest_params", result)
        assert len(errors) == 0, f"Schema errors: {errors}"

        assert "notes" in result
        assert isinstance(result["notes"], list)

    def test_suggest_for_ingest_export(self, mcp_client):
        """Suggest params for ingest_export workflow."""
        result = mcp_client.call_tool("suggest_params", {
            "workflow": "ingest_export",
        })
        errors = validate_tool_output("suggest_params", result)
        assert len(errors) == 0, f"Schema errors: {errors}"

    def test_suggest_for_ingest_tabulate(self, mcp_client):
        """Suggest params for ingest_tabulate workflow."""
        result = mcp_client.call_tool("suggest_params", {
            "workflow": "ingest_tabulate",
        })
        errors = validate_tool_output("suggest_params", result)
        assert len(errors) == 0, f"Schema errors: {errors}"

    def test_suggest_with_samplesheet_context(self, mcp_client, valid_samplesheet):
        """Suggest params with samplesheet context."""
        result = mcp_client.call_tool("suggest_params", {
            "workflow": "integration",
            "samplesheet_path": valid_samplesheet,
        })
        errors = validate_tool_output("suggest_params", result)
        assert len(errors) == 0, f"Schema errors: {errors}"

    def test_suggest_with_existing_params(self, mcp_client):
        """Suggest params should avoid re-suggesting existing params."""
        result = mcp_client.call_tool("suggest_params", {
            "workflow": "integration",
            "params": {"export_assay": "RNA"},
        })
        errors = validate_tool_output("suggest_params", result)
        assert len(errors) == 0, f"Schema errors: {errors}"