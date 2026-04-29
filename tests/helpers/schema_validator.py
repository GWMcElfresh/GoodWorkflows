"""
JSON Schema validators for all MCP server output types.

Every MCP tool output must conform to its schema. These validators
are used in unit tests to ensure strict structural correctness.
"""

from typing import Any, Dict, List


# ---------------------------------------------------------------------------
# JSON Schema definitions for all MCP output types
# ---------------------------------------------------------------------------

REPOSITORY_DISCOVERY_SCHEMA: Dict[str, Any] = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "required": ["workflows", "modules", "profiles", "config_structure", "params"],
    "properties": {
        "workflows": {
            "type": "array",
            "items": {
                "type": "object",
                "required": ["name", "entrypoint", "stages", "type", "uses_modules"],
                "properties": {
                    "name": {"type": "string"},
                    "entrypoint": {"type": "string"},
                    "stages": {
                        "type": "array",
                        "items": {"type": "string"},
                    },
                    "type": {"type": "string", "enum": ["gpu", "cpu", "mixed"]},
                    "uses_modules": {
                        "type": "array",
                        "items": {"type": "string"},
                    },
                    "description": {"type": "string"},
                },
            },
        },
        "modules": {
            "type": "array",
            "items": {
                "type": "object",
                "required": ["name", "path", "inputs", "outputs", "label", "has_stub", "is_gpu"],
                "properties": {
                    "name": {"type": "string"},
                    "path": {"type": "string"},
                    "inputs": {"type": "array", "items": {"type": "string"}},
                    "outputs": {"type": "array", "items": {"type": "string"}},
                    "label": {"type": "string"},
                    "has_stub": {"type": "boolean"},
                    "container": {"type": "string"},
                    "is_gpu": {"type": "boolean"},
                    "publish_dir": {"type": "string"},
                },
            },
        },
        "profiles": {
            "type": "array",
            "items": {"type": "string"},
        },
        "config_structure": {
            "type": "object",
            "required": ["base", "profiles"],
            "properties": {
                "base": {"type": "string"},
                "profiles": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "required": ["name", "config_file", "description", "is_active"],
                        "properties": {
                            "name": {"type": "string"},
                            "config_file": {"type": "string"},
                            "description": {"type": "string"},
                            "is_active": {"type": "boolean"},
                        },
                    },
                },
            },
        },
        "params": {
            "type": "object",
            "required": ["required", "optional", "defaults"],
            "properties": {
                "required": {"type": "array", "items": {"type": "string"}},
                "optional": {"type": "array", "items": {"type": "string"}},
                "defaults": {"type": "object"},
            },
        },
    },
}

DAG_SCHEMA: Dict[str, Any] = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "required": ["nodes", "edges", "branches", "collect_points", "fan_in_points", "fan_out_points", "gpu_nodes"],
    "properties": {
        "nodes": {
            "type": "array",
            "items": {
                "type": "object",
                "required": ["id", "type"],
                "properties": {
                    "id": {"type": "string"},
                    "type": {"type": "string", "enum": ["process", "collect", "map", "channel"]},
                    "label": {"type": "string"},
                    "is_gpu": {"type": "boolean"},
                    "module_path": {"type": "string"},
                },
            },
        },
        "edges": {
            "type": "array",
            "items": {
                "type": "object",
                "required": ["from", "to"],
                "properties": {
                    "from": {"type": "string"},
                    "to": {"type": "string"},
                    "channel_type": {"type": "string"},
                    "is_collect": {"type": "boolean"},
                },
            },
        },
        "branches": {
            "type": "array",
            "items": {
                "type": "object",
                "required": ["name", "nodes"],
                "properties": {
                    "name": {"type": "string"},
                    "nodes": {"type": "array", "items": {"type": "string"}},
                    "description": {"type": "string"},
                },
            },
        },
        "collect_points": {"type": "array", "items": {"type": "string"}},
        "fan_in_points": {
            "type": "array",
            "items": {
                "type": "object",
                "required": ["node", "sources"],
                "properties": {
                    "node": {"type": "string"},
                    "sources": {"type": "array", "items": {"type": "string"}},
                },
            },
        },
        "fan_out_points": {
            "type": "array",
            "items": {
                "type": "object",
                "required": ["node", "targets"],
                "properties": {
                    "node": {"type": "string"},
                    "targets": {"type": "array", "items": {"type": "string"}},
                },
            },
        },
        "gpu_nodes": {"type": "array", "items": {"type": "string"}},
    },
}

WORKFLOW_DETAILS_SCHEMA: Dict[str, Any] = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "required": ["name", "entrypoint", "dag", "channels", "module_connections"],
    "properties": {
        "name": {"type": "string"},
        "entrypoint": {"type": "string"},
        "dag": DAG_SCHEMA,
        "channels": {
            "type": "array",
            "items": {
                "type": "object",
                "required": ["name", "type", "source", "targets"],
                "properties": {
                    "name": {"type": "string"},
                    "type": {"type": "string"},
                    "source": {"type": "string"},
                    "targets": {"type": "array", "items": {"type": "string"}},
                },
            },
        },
        "module_connections": {
            "type": "array",
            "items": {
                "type": "object",
                "required": ["module", "input_channels", "output_channels"],
                "properties": {
                    "module": {"type": "string"},
                    "input_channels": {"type": "array", "items": {"type": "string"}},
                    "output_channels": {"type": "array", "items": {"type": "string"}},
                },
            },
        },
    },
}

PIPELINE_SUGGESTION_SCHEMA: Dict[str, Any] = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "required": ["workflow_plan", "excluded", "reasoning"],
    "properties": {
        "workflow_plan": {"type": "array", "items": {"type": "string"}},
        "excluded": {"type": "array", "items": {"type": "string"}},
        "reasoning": {"type": "string"},
        "warnings": {"type": "array", "items": {"type": "string"}},
    },
}

COMPOSE_RESULT_SCHEMA: Dict[str, Any] = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "required": ["workflow_name", "workflow_content", "warnings"],
    "properties": {
        "workflow_name": {"type": "string"},
        "workflow_content": {"type": "string"},
        "warnings": {"type": "array", "items": {"type": "string"}},
    },
}

VALIDATION_RESULT_SCHEMA: Dict[str, Any] = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "required": ["valid", "errors", "warnings", "missing_params", "gpu_conflicts", "profile_issues"],
    "properties": {
        "valid": {"type": "boolean"},
        "errors": {"type": "array", "items": {"type": "string"}},
        "warnings": {"type": "array", "items": {"type": "string"}},
        "missing_params": {"type": "array", "items": {"type": "string"}},
        "gpu_conflicts": {"type": "array", "items": {"type": "string"}},
        "profile_issues": {"type": "array", "items": {"type": "string"}},
    },
}

RUN_RESULT_SCHEMA: Dict[str, Any] = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "required": ["run_id", "logs_path", "status"],
    "properties": {
        "run_id": {"type": "string"},
        "logs_path": {"type": "string"},
        "status": {"type": "string", "enum": ["running", "completed", "failed"]},
        "exit_code": {"type": "integer"},
        "stdout_summary": {"type": "string"},
    },
}

SAMPLESHEET_ANALYSIS_SCHEMA: Dict[str, Any] = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "required": [
        "valid", "row_count", "required_fields_present", "required_fields_missing",
        "species_detected", "species_mix", "needs_harmonization", "warnings", "errors",
    ],
    "properties": {
        "valid": {"type": "boolean"},
        "row_count": {"type": "integer"},
        "required_fields_present": {"type": "array", "items": {"type": "string"}},
        "required_fields_missing": {"type": "array", "items": {"type": "string"}},
        "species_detected": {"type": "array", "items": {"type": "string"}},
        "species_mix": {"type": "boolean"},
        "needs_harmonization": {"type": "boolean"},
        "warnings": {"type": "array", "items": {"type": "string"}},
        "errors": {"type": "array", "items": {"type": "string"}},
    },
}

PARAM_SUGGESTION_SCHEMA: Dict[str, Any] = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "required": ["notes"],
    "properties": {
        "export_assay": {"type": "string"},
        "scmodal_params": {"type": "object"},
        "tabulate_columns": {"type": "array", "items": {"type": "string"}},
        "tabulate_id_cols": {"type": "array", "items": {"type": "string"}},
        "notes": {"type": "array", "items": {"type": "string"}},
    },
}

# Map tool names to their output schemas
TOOL_SCHEMAS: Dict[str, Dict[str, Any]] = {
    "discover_repository": REPOSITORY_DISCOVERY_SCHEMA,
    "get_workflow_details": WORKFLOW_DETAILS_SCHEMA,
    "get_dag": DAG_SCHEMA,
    "suggest_pipeline": PIPELINE_SUGGESTION_SCHEMA,
    "compose_workflow": COMPOSE_RESULT_SCHEMA,
    "validate_workflow": VALIDATION_RESULT_SCHEMA,
    "run_workflow": RUN_RESULT_SCHEMA,
    "resume_run": RUN_RESULT_SCHEMA,
    "analyze_samplesheet": SAMPLESHEET_ANALYSIS_SCHEMA,
    "suggest_params": PARAM_SUGGESTION_SCHEMA,
}


def validate_schema(instance: dict, schema: dict) -> List[str]:
    """
    Validate a JSON instance against a JSON Schema.

    This is a lightweight validator that checks required fields,
    types, and enum values. It does not implement the full JSON Schema
    spec but covers the patterns used by the MCP server.

    Args:
        instance: The JSON object to validate.
        schema: The JSON Schema to validate against.

    Returns:
        List of error messages. Empty list means valid.
    """
    errors: List[str] = []

    if schema.get("type") == "object":
        if not isinstance(instance, dict):
            errors.append(f"Expected object, got {type(instance).__name__}")
            return errors

        # Check required properties
        for required in schema.get("required", []):
            if required not in instance:
                errors.append(f"Missing required property: '{required}'")

        # Check property schemas
        properties = schema.get("properties", {})
        for prop_name, prop_schema in properties.items():
            if prop_name in instance:
                prop_errors = _validate_value(
                    instance[prop_name], prop_schema, f"'{prop_name}'"
                )
                errors.extend(prop_errors)

    return errors


def _validate_value(value: Any, schema: dict, path: str) -> List[str]:
    """Validate a single value against its schema."""
    errors: List[str] = []

    schema_type = schema.get("type")
    if schema_type == "string":
        if not isinstance(value, str):
            errors.append(f"{path}: expected string, got {type(value).__name__}")
        elif "enum" in schema and value not in schema["enum"]:
            errors.append(f"{path}: '{value}' not in allowed values: {schema['enum']}")

    elif schema_type == "integer":
        if not isinstance(value, int) or isinstance(value, bool):
            errors.append(f"{path}: expected integer, got {type(value).__name__}")

    elif schema_type == "boolean":
        if not isinstance(value, bool):
            errors.append(f"{path}: expected boolean, got {type(value).__name__}")

    elif schema_type == "array":
        if not isinstance(value, list):
            errors.append(f"{path}: expected array, got {type(value).__name__}")
        else:
            items_schema = schema.get("items", {})
            for i, item in enumerate(value):
                item_errors = _validate_value(item, items_schema, f"{path}[{i}]")
                errors.extend(item_errors)

    elif schema_type == "object":
        if not isinstance(value, dict):
            errors.append(f"{path}: expected object, got {type(value).__name__}")
        else:
            for required in schema.get("required", []):
                if required not in value:
                    errors.append(f"{path}: missing required property '{required}'")
            for prop_name, prop_schema in schema.get("properties", {}).items():
                if prop_name in value:
                    prop_errors = _validate_value(
                        value[prop_name], prop_schema, f"{path}.{prop_name}"
                    )
                    errors.extend(prop_errors)

    return errors


def validate_tool_output(tool_name: str, output: dict) -> List[str]:
    """
    Validate a tool's output against its expected schema.

    Args:
        tool_name: Name of the MCP tool.
        output: The parsed JSON output from the tool.

    Returns:
        List of validation error messages. Empty list means valid.
    """
    schema = TOOL_SCHEMAS.get(tool_name)
    if schema is None:
        return [f"No schema defined for tool: {tool_name}"]

    return validate_schema(output, schema)