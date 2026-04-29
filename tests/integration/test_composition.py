"""
Integration tests for pipeline composition.

Validates suggest_pipeline and compose_workflow against the real repo.
"""

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from helpers.schema_validator import validate_tool_output
from helpers.dsl2_validator import validate_dsl2_workflow


class TestSuggestPipeline:
    """Validate suggest_pipeline tool."""

    def test_suggest_without_gpu(self, mcp_client):
        """Suggest a pipeline excluding GPU modules."""
        result = mcp_client.call_tool("suggest_pipeline", {
            "goal": "cross-species integration without GPU",
            "constraints": {"no_gpu": True},
        })
        errors = validate_tool_output("suggest_pipeline", result)
        assert len(errors) == 0, f"Schema errors: {errors}"

        assert len(result["workflow_plan"]) > 0, "No modules in plan"
        assert "SCMODAL_INTEGRATE" not in result["workflow_plan"], (
            "GPU module should be excluded"
        )
        assert "SCMODAL_INTEGRATE" in result["excluded"], (
            "GPU module should be in excluded list"
        )

    def test_suggest_with_gpu(self, mcp_client):
        """Suggest a pipeline including GPU modules."""
        result = mcp_client.call_tool("suggest_pipeline", {
            "goal": "full integration with GPU",
            "constraints": {"no_gpu": False},
        })
        errors = validate_tool_output("suggest_pipeline", result)
        assert len(errors) == 0, f"Schema errors: {errors}"

        assert len(result["workflow_plan"]) > 0, "No modules in plan"

    def test_suggest_has_reasoning(self, mcp_client):
        """Suggestion should include reasoning."""
        result = mcp_client.call_tool("suggest_pipeline", {
            "goal": "simple export pipeline",
        })
        assert result["reasoning"], "No reasoning provided"


class TestComposeWorkflow:
    """Validate compose_workflow tool."""

    def test_compose_without_tabulate(self, mcp_client, repo_root):
        """Compose a workflow without the tabulate branch."""
        result = mcp_client.call_tool("compose_workflow", {
            "name": "test_no_tabulate",
            "modules": ["INGEST", "EXPORT_COUNTS", "GENE_HARMONIZE"],
            "with_tabulate": False,
        })
        errors = validate_tool_output("compose_workflow", result)
        assert len(errors) == 0, f"Schema errors: {errors}"

        assert result["workflow_name"] == "test_no_tabulate"
        assert result["workflow_content"], "No workflow content generated"

        # Validate DSL2 syntax
        is_valid, issues = validate_dsl2_workflow(
            result["workflow_content"], str(repo_root)
        )
        assert is_valid, f"Generated workflow has DSL2 issues: {issues}"

    def test_compose_with_tabulate(self, mcp_client, repo_root):
        """Compose a workflow WITH the tabulate branch."""
        result = mcp_client.call_tool("compose_workflow", {
            "name": "test_with_tabulate",
            "modules": ["INGEST", "EXPORT_COUNTS", "GENE_HARMONIZE"],
            "with_tabulate": True,
        })
        errors = validate_tool_output("compose_workflow", result)
        assert len(errors) == 0, f"Schema errors: {errors}"

        assert result["workflow_name"] == "test_with_tabulate"

        # Validate DSL2 syntax
        is_valid, issues = validate_dsl2_workflow(
            result["workflow_content"], str(repo_root)
        )
        assert is_valid, f"Generated workflow has DSL2 issues: {issues}"

        # Should contain tabulate-related modules
        content = result["workflow_content"]
        assert "INGEST_METADATA" in content or "TABULATE" in content, (
            "Tabulate branch modules not found in generated workflow"
        )

    def test_compose_has_valid_shebang(self, mcp_client):
        """Generated workflow should have valid shebang."""
        result = mcp_client.call_tool("compose_workflow", {
            "name": "test_shebang",
            "modules": ["INGEST"],
        })
        assert result["workflow_content"].startswith("#!/usr/bin/env nextflow"), (
            "Missing shebang"
        )

    def test_compose_has_workflow_block(self, mcp_client):
        """Generated workflow should have a workflow block."""
        result = mcp_client.call_tool("compose_workflow", {
            "name": "test_block",
            "modules": ["INGEST"],
        })
        assert "workflow" in result["workflow_content"], (
            "No workflow block in generated content"
        )

    def test_compose_includes_modules(self, mcp_client):
        """Generated workflow should include the requested modules."""
        result = mcp_client.call_tool("compose_workflow", {
            "name": "test_includes",
            "modules": ["INGEST", "EXPORT_COUNTS"],
        })
        content = result["workflow_content"]
        assert "INGEST" in content, "INGEST not found in workflow"
        assert "EXPORT_COUNTS" in content, "EXPORT_COUNTS not found in workflow"


class TestValidation:
    """Validate validate_workflow tool."""

    def test_validate_integration_with_test_profile(self, mcp_client):
        """Integration workflow should validate with test profile."""
        result = mcp_client.call_tool("validate_workflow", {
            "workflow": "integration",
            "profile": "test",
        })
        errors = validate_tool_output("validate_workflow", result)
        assert len(errors) == 0, f"Schema errors: {errors}"

        # With test profile, should be valid (stub mode)
        assert result["valid"] is True, (
            f"Expected valid, got errors: {result.get('errors')}"
        )

    def test_validate_ingest_export_with_test_profile(self, mcp_client):
        """Ingest_export should validate with test profile."""
        result = mcp_client.call_tool("validate_workflow", {
            "workflow": "ingest_export",
            "profile": "test",
        })
        errors = validate_tool_output("validate_workflow", result)
        assert len(errors) == 0, f"Schema errors: {errors}"
        assert result["valid"] is True, (
            f"Expected valid, got errors: {result.get('errors')}"
        )

    def test_validate_ingest_tabulate_with_test_profile(self, mcp_client):
        """Ingest_tabulate should validate with test profile."""
        result = mcp_client.call_tool("validate_workflow", {
            "workflow": "ingest_tabulate",
            "profile": "test",
        })
        errors = validate_tool_output("validate_workflow", result)
        assert len(errors) == 0, f"Schema errors: {errors}"
        assert result["valid"] is True, (
            f"Expected valid, got errors: {result.get('errors')}"
        )

    def test_validate_unknown_workflow_fails(self, mcp_client):
        """Unknown workflow should fail validation."""
        result = mcp_client.call_tool("validate_workflow", {
            "workflow": "nonexistent_workflow",
            "profile": "test",
        })
        assert result["valid"] is False, "Unknown workflow should not be valid"
        assert len(result["errors"]) > 0, "Should have errors for unknown workflow"

    def test_validate_has_structured_output(self, mcp_client):
        """Validation output should have all required fields."""
        result = mcp_client.call_tool("validate_workflow", {
            "workflow": "integration",
            "profile": "test",
        })
        assert "valid" in result
        assert "errors" in result
        assert "warnings" in result
        assert "missing_params" in result
        assert "gpu_conflicts" in result
        assert "profile_issues" in result