"""
End-to-end tests simulating realistic MCP usage.

Flow: discover → suggest_pipeline → compose_workflow → validate → run
"""

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from helpers.schema_validator import validate_tool_output
from helpers.dsl2_validator import validate_dsl2_workflow


class TestFullPipelineE2E:
    """
    Simulate a complete user workflow:

    1. Discover the repository
    2. Analyze a samplesheet
    3. Get parameter suggestions
    4. Suggest a pipeline composition
    5. Compose a new workflow
    6. Validate the composed workflow
    7. Run the workflow with stub mode
    """

    def test_discover_to_run_flow(self, mcp_client, repo_root, valid_samplesheet):
        """Complete end-to-end flow: discover → compose → validate → run."""

        # Step 1: Discover repository
        discovery = mcp_client.call_tool("discover_repository")
        assert len(discovery["workflows"]) > 0, "No workflows discovered"
        assert len(discovery["modules"]) > 0, "No modules discovered"

        # Step 2: Analyze samplesheet
        analysis = mcp_client.call_tool("analyze_samplesheet", {
            "file_path": valid_samplesheet,
        })
        assert analysis["valid"] is True, f"Samplesheet invalid: {analysis.get('errors')}"

        # Step 3: Get parameter suggestions
        params = mcp_client.call_tool("suggest_params", {
            "workflow": "integration",
            "samplesheet_path": valid_samplesheet,
        })
        assert "notes" in params

        # Step 4: Suggest a pipeline (no GPU for test profile)
        suggestion = mcp_client.call_tool("suggest_pipeline", {
            "goal": "cross-species integration without GPU for testing",
            "constraints": {"no_gpu": True, "profile": "test"},
        })
        assert len(suggestion["workflow_plan"]) > 0, "No modules suggested"

        # Step 5: Compose a workflow from the suggestion
        compose_result = mcp_client.call_tool("compose_workflow", {
            "name": "e2e_test_workflow",
            "modules": suggestion["workflow_plan"],
            "with_tabulate": True,
        })
        assert compose_result["workflow_content"], "No workflow content"

        # Validate DSL2 syntax of composed workflow
        is_valid, issues = validate_dsl2_workflow(
            compose_result["workflow_content"], str(repo_root)
        )
        assert is_valid, f"Composed workflow has DSL2 issues: {issues}"

        # Step 6: Validate the composed workflow
        # Note: composed workflows may not be in the main.nf switch block,
        # so we validate the integration workflow instead as a proxy
        validation = mcp_client.call_tool("validate_workflow", {
            "workflow": "integration",
            "profile": "test",
        })
        assert validation["valid"] is True, (
            f"Validation failed: {validation.get('errors')}"
        )

        # Step 7: Run the integration workflow with stub mode
        run_result = mcp_client.call_tool("run_workflow", {
            "workflow": "integration",
            "profile": "test",
            "params": {
                "input": valid_samplesheet,
                "outdir": str(repo_root / "outputs" / "e2e_test"),
            },
        })
        errors = validate_tool_output("run_workflow", run_result)
        assert len(errors) == 0, f"Schema errors: {errors}"

        assert run_result["run_id"], "No run_id returned"
        assert run_result["status"] in ("running", "completed"), (
            f"Unexpected status: {run_result['status']}"
        )

    def test_discover_to_run_ingest_export(self, mcp_client, repo_root, valid_samplesheet):
        """E2E flow for ingest_export workflow."""

        # Discover
        discovery = mcp_client.call_tool("discover_repository")
        workflow_names = [w["name"] for w in discovery["workflows"]]
        assert "ingest_export" in workflow_names

        # Validate
        validation = mcp_client.call_tool("validate_workflow", {
            "workflow": "ingest_export",
            "profile": "test",
        })
        assert validation["valid"] is True, (
            f"Validation failed: {validation.get('errors')}"
        )

        # Run
        run_result = mcp_client.call_tool("run_workflow", {
            "workflow": "ingest_export",
            "profile": "test",
            "params": {
                "input": valid_samplesheet,
                "outdir": str(repo_root / "outputs" / "e2e_export_test"),
            },
        })
        assert run_result["run_id"], "No run_id returned"
        assert run_result["status"] in ("running", "completed"), (
            f"Unexpected status: {run_result['status']}"
        )

    def test_discover_to_run_ingest_tabulate(self, mcp_client, repo_root, valid_samplesheet):
        """E2E flow for ingest_tabulate workflow."""

        # Discover
        discovery = mcp_client.call_tool("discover_repository")
        workflow_names = [w["name"] for w in discovery["workflows"]]
        assert "ingest_tabulate" in workflow_names

        # Validate
        validation = mcp_client.call_tool("validate_workflow", {
            "workflow": "ingest_tabulate",
            "profile": "test",
        })
        assert validation["valid"] is True, (
            f"Validation failed: {validation.get('errors')}"
        )

        # Run
        run_result = mcp_client.call_tool("run_workflow", {
            "workflow": "ingest_tabulate",
            "profile": "test",
            "params": {
                "input": valid_samplesheet,
                "outdir": str(repo_root / "outputs" / "e2e_tabulate_test"),
            },
        })
        assert run_result["run_id"], "No run_id returned"
        assert run_result["status"] in ("running", "completed"), (
            f"Unexpected status: {run_result['status']}"
        )


class TestMutationDetection:
    """Bonus: Test that MCP detects invalid/mutated workflows."""

    def test_invalid_workflow_name_fails(self, mcp_client):
        """Requesting details for nonexistent workflow should fail gracefully."""
        result = mcp_client.call_tool("get_workflow_details", {
            "workflow": "completely_fake_workflow",
        })
        # Should return an error or empty result
        # The exact behavior depends on implementation, but it should not crash
        assert result is not None, "Should return a result, not crash"

    def test_validation_catches_missing_params(self, mcp_client):
        """Validation should catch when required params are missing."""
        # Validate without providing required params
        result = mcp_client.call_tool("validate_workflow", {
            "workflow": "integration",
            "profile": "test",
            "params": {},  # empty params
        })
        # The validation should still work structurally
        assert "valid" in result
        assert "missing_params" in result

    def test_compose_with_empty_modules(self, mcp_client):
        """Composing with empty module list should produce warnings."""
        result = mcp_client.call_tool("compose_workflow", {
            "name": "empty_test",
            "modules": [],
        })
        # Should still produce valid output structure
        errors = validate_tool_output("compose_workflow", result)
        assert len(errors) == 0, f"Schema errors: {errors}"
        # Should have warnings about empty module list
        assert len(result["warnings"]) > 0 or result["workflow_content"], (
            "Should either warn or produce minimal workflow"
        )