"""
Integration tests for repository discovery.

Runs against the real GoodWorkflows repo via the MCP server.
Validates that all workflows, modules, configs, and params are
correctly discovered and structured.
"""

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from helpers.schema_validator import validate_tool_output


class TestRepositoryDiscovery:
    """Validate discover_repository against the real repo."""

    def test_discovers_all_workflows(self, mcp_client):
        """All three workflows should be discovered."""
        result = mcp_client.call_tool("discover_repository")
        errors = validate_tool_output("discover_repository", result)
        assert len(errors) == 0, f"Schema errors: {errors}"

        workflow_names = [w["name"] for w in result["workflows"]]
        assert "integration" in workflow_names, "Missing integration workflow"
        assert "ingest_export" in workflow_names, "Missing ingest_export workflow"
        assert "ingest_tabulate" in workflow_names, "Missing ingest_tabulate workflow"

    def test_workflows_have_stages(self, mcp_client):
        """Each workflow should list its stages."""
        result = mcp_client.call_tool("discover_repository")
        for wf in result["workflows"]:
            assert len(wf["stages"]) > 0, (
                f"Workflow '{wf['name']}' has no stages"
            )

    def test_workflows_have_valid_type(self, mcp_client):
        """Each workflow type should be gpu, cpu, or mixed."""
        result = mcp_client.call_tool("discover_repository")
        valid_types = {"gpu", "cpu", "mixed"}
        for wf in result["workflows"]:
            assert wf["type"] in valid_types, (
                f"Workflow '{wf['name']}' has invalid type: {wf['type']}"
            )

    def test_discovers_all_modules(self, mcp_client):
        """All modules should be discovered with correct metadata."""
        result = mcp_client.call_tool("discover_repository")
        modules = result["modules"]
        assert len(modules) > 0, "No modules discovered"

        module_names = [m["name"] for m in modules]

        # Core pipeline modules
        expected_modules = [
            "INGEST", "EXPORT_COUNTS", "GENE_HARMONIZE", "SCMODAL_INTEGRATE",
            "INGEST_METADATA", "TABULATE",
        ]
        for expected in expected_modules:
            assert expected in module_names, f"Missing module: {expected}"

    def test_modules_have_stubs(self, mcp_client):
        """Every module should have a stub block."""
        result = mcp_client.call_tool("discover_repository")
        for module in result["modules"]:
            assert module["has_stub"] is True, (
                f"Module '{module['name']}' missing stub block"
            )

    def test_modules_have_labels(self, mcp_client):
        """Every module should have a process label."""
        result = mcp_client.call_tool("discover_repository")
        for module in result["modules"]:
            assert module["label"], (
                f"Module '{module['name']}' has no label"
            )

    def test_gpu_modules_flagged(self, mcp_client):
        """GPU modules should be flagged as is_gpu=True."""
        result = mcp_client.call_tool("discover_repository")
        gpu_modules = [m for m in result["modules"] if m["is_gpu"]]
        # SCMODAL_INTEGRATE should be GPU
        scmodal = [m for m in result["modules"] if m["name"] == "SCMODAL_INTEGRATE"]
        if scmodal:
            assert scmodal[0]["is_gpu"] is True, "SCMODAL_INTEGRATE should be GPU"

    def test_config_structure_valid(self, mcp_client):
        """Config inheritance structure should be valid."""
        result = mcp_client.call_tool("discover_repository")
        config = result["config_structure"]
        assert config["base"], "No base config path"
        assert len(config["profiles"]) > 0, "No profiles discovered"

        profile_names = [p["name"] for p in config["profiles"]]
        assert "test" in profile_names, "Missing test profile"
        assert "local" in profile_names, "Missing local profile"

    def test_params_structure_valid(self, mcp_client):
        """Params should list required, optional, and defaults."""
        result = mcp_client.call_tool("discover_repository")
        params = result["params"]
        assert "required" in params
        assert "optional" in params
        assert "defaults" in params
        assert isinstance(params["required"], list)
        assert isinstance(params["optional"], list)
        assert isinstance(params["defaults"], dict)

    def test_profiles_listed(self, mcp_client):
        """All execution profiles should be listed."""
        result = mcp_client.call_tool("discover_repository")
        profiles = result["profiles"]
        assert "test" in profiles
        assert "local" in profiles


class TestWorkflowDetails:
    """Validate get_workflow_details for each workflow."""

    def test_integration_workflow_details(self, mcp_client):
        """Integration workflow should have full DAG and channels."""
        result = mcp_client.call_tool("get_workflow_details", {
            "workflow": "integration",
        })
        errors = validate_tool_output("get_workflow_details", result)
        assert len(errors) == 0, f"Schema errors: {errors}"

        assert result["name"] == "integration"
        assert "dag" in result
        assert "channels" in result
        assert "module_connections" in result

    def test_ingest_export_workflow_details(self, mcp_client):
        """Ingest_export workflow should have details."""
        result = mcp_client.call_tool("get_workflow_details", {
            "workflow": "ingest_export",
        })
        errors = validate_tool_output("get_workflow_details", result)
        assert len(errors) == 0, f"Schema errors: {errors}"
        assert result["name"] == "ingest_export"

    def test_ingest_tabulate_workflow_details(self, mcp_client):
        """Ingest_tabulate workflow should have details."""
        result = mcp_client.call_tool("get_workflow_details", {
            "workflow": "ingest_tabulate",
        })
        errors = validate_tool_output("get_workflow_details", result)
        assert len(errors) == 0, f"Schema errors: {errors}"
        assert result["name"] == "ingest_tabulate"


class TestDagExtraction:
    """Validate get_dag returns correct graph structure."""

    def test_dag_has_correct_structure(self, mcp_client):
        """DAG should have nodes, edges, branches, and collect points."""
        result = mcp_client.call_tool("get_dag")
        errors = validate_tool_output("get_dag", result)
        assert len(errors) == 0, f"Schema errors: {errors}"

        assert len(result["nodes"]) > 0, "DAG has no nodes"
        assert len(result["edges"]) > 0, "DAG has no edges"

    def test_dag_contains_main_pipeline_nodes(self, mcp_client):
        """Main pipeline nodes should be in the DAG."""
        result = mcp_client.call_tool("get_dag")
        node_ids = [n["id"] for n in result["nodes"]]

        expected_nodes = ["INGEST", "EXPORT_COUNTS", "GENE_HARMONIZE", "SCMODAL_INTEGRATE"]
        for node in expected_nodes:
            assert node in node_ids, f"Missing DAG node: {node}"

    def test_dag_contains_metadata_branch(self, mcp_client):
        """Metadata branch should be in the DAG."""
        result = mcp_client.call_tool("get_dag")
        node_ids = [n["id"] for n in result["nodes"]]

        assert "INGEST_METADATA" in node_ids, "Missing INGEST_METADATA"
        assert "TABULATE" in node_ids, "Missing TABULATE"

    def test_dag_has_branches(self, mcp_client):
        """DAG should identify branches."""
        result = mcp_client.call_tool("get_dag")
        branches = result["branches"]
        assert len(branches) > 0, "No branches in DAG"

        branch_names = [b["name"] for b in branches]
        assert "metadata" in branch_names, "Missing metadata branch"

    def test_dag_has_collect_points(self, mcp_client):
        """DAG should identify .collect() points."""
        result = mcp_client.call_tool("get_dag")
        # collect_points may be empty for some workflows, but the field must exist
        assert isinstance(result["collect_points"], list)

    def test_dag_has_gpu_nodes(self, mcp_client):
        """DAG should identify GPU nodes."""
        result = mcp_client.call_tool("get_dag")
        gpu_nodes = result["gpu_nodes"]
        assert isinstance(gpu_nodes, list)
        # SCMODAL_INTEGRATE should be in GPU nodes if present
        if "SCMODAL_INTEGRATE" in [n["id"] for n in result["nodes"]]:
            assert "SCMODAL_INTEGRATE" in gpu_nodes, (
                "SCMODAL_INTEGRATE should be in gpu_nodes"
            )

    def test_dag_edges_connect_valid_nodes(self, mcp_client):
        """All edges should connect existing nodes."""
        result = mcp_client.call_tool("get_dag")
        node_ids = {n["id"] for n in result["nodes"]}

        for edge in result["edges"]:
            assert edge["from"] in node_ids, (
                f"Edge 'from' references unknown node: {edge['from']}"
            )
            assert edge["to"] in node_ids, (
                f"Edge 'to' references unknown node: {edge['to']}"
            )