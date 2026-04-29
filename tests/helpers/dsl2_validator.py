"""
DSL2 syntax validator for generated Nextflow workflow files.

Validates that composed workflows are syntactically valid DSL2
and follow GoodWorkflows conventions.
"""

import re
from pathlib import Path
from typing import List, Tuple


def validate_dsl2_workflow(content: str, repo_root: str) -> Tuple[bool, List[str]]:
    """
    Validate a generated DSL2 workflow string.

    Checks:
    - Valid shebang
    - Include statements reference real modules
    - workflow { take: / main: / emit: } structure
    - No duplicate channel names
    - .collect() calls precede multi-input processes
    - All referenced modules exist

    Args:
        content: The workflow file content as a string.
        repo_root: Path to the repository root for resolving module paths.

    Returns:
        Tuple of (is_valid, list_of_issues).
    """
    issues: List[str] = []
    repo_path = Path(repo_root)

    lines = content.split("\n")

    # Check shebang
    if not lines or not lines[0].startswith("#!/usr/bin/env nextflow"):
        issues.append("Missing or invalid shebang: should be '#!/usr/bin/env nextflow'")

    # Check for workflow block
    has_workflow = False
    has_take = False
    has_main = False
    has_emit = False
    in_workflow = False

    for line in lines:
        stripped = line.strip()

        if re.match(r"^workflow\s+\w+\s*\{", stripped):
            has_workflow = True
            in_workflow = True
            continue

        if in_workflow:
            if stripped == "take:":
                has_take = True
            elif stripped == "main:":
                has_main = True
            elif stripped == "emit:":
                has_emit = True
            elif stripped == "}":
                in_workflow = False

    if not has_workflow:
        issues.append("No workflow block found")
    if not has_take:
        issues.append("Workflow missing 'take:' section")
    if not has_main:
        issues.append("Workflow missing 'main:' section")
    if not has_emit:
        issues.append("Workflow missing 'emit:' section")

    # Check include statements reference real files
    include_pattern = re.compile(r"include\s*\{\s*(\w+)\s*\}\s*from\s*'([^']+)'")
    for line in lines:
        match = include_pattern.search(line)
        if match:
            module_name = match.group(1)
            include_path = match.group(2)

            # Resolve the include path relative to where the workflow would be
            # Generated workflows are placed in workflows/ directory
            workflows_dir = repo_path / "workflows"
            resolved = (workflows_dir / include_path).resolve()

            if not resolved.exists():
                issues.append(
                    f"Include path for '{module_name}' does not exist: {include_path} "
                    f"(resolved: {resolved})"
                )

    # Check for duplicate channel assignments
    channel_assignments: List[str] = []
    assign_pattern = re.compile(r"^\s*(\w+)\s*=\s*\w+\.out\.\w+")
    for line in lines:
        match = assign_pattern.search(line)
        if match:
            ch_name = match.group(1)
            if ch_name in channel_assignments:
                issues.append(f"Duplicate channel assignment: '{ch_name}'")
            channel_assignments.append(ch_name)

    # Check .collect() placement
    # Find processes that take collected channels
    process_calls = []
    call_pattern = re.compile(r"^\s*(\w+)\((\w+)\)")
    for i, line in enumerate(lines):
        match = call_pattern.search(line)
        if match:
            process_name = match.group(1)
            input_ch = match.group(2)
            process_calls.append((i, process_name, input_ch))

    # Check that collected channels are actually collected before use
    for i, proc_name, input_ch in process_calls:
        if input_ch.endswith("_collected"):
            # Find the .collect() call for the base channel
            base_ch = input_ch.replace("_collected", "")
            collect_found = False
            for j in range(i):
                if f"{base_ch}.collect()" in lines[j]:
                    collect_found = True
                    break
            if not collect_found:
                issues.append(
                    f"Process '{proc_name}' uses collected channel '{input_ch}' "
                    f"but no .collect() call found for '{base_ch}' before line {i + 1}"
                )

    # Check for basic syntax issues
    # Unclosed braces
    open_braces = content.count("{")
    close_braces = content.count("}")
    if open_braces != close_braces:
        issues.append(
            f"Unbalanced braces: {open_braces} open, {close_braces} close"
        )

    return len(issues) == 0, issues


def validate_workflow_file(file_path: str, repo_root: str) -> Tuple[bool, List[str]]:
    """
    Validate a workflow file on disk.

    Args:
        file_path: Path to the workflow .nf file.
        repo_root: Path to the repository root.

    Returns:
        Tuple of (is_valid, list_of_issues).
    """
    path = Path(file_path)
    if not path.exists():
        return False, [f"File not found: {file_path}"]

    content = path.read_text()
    return validate_dsl2_workflow(content, repo_root)


def check_module_exists(module_name: str, repo_root: str) -> bool:
    """
    Check if a module exists in the repository.

    Args:
        module_name: Name of the module (e.g., 'INGEST', 'EXPORT_COUNTS').
        repo_root: Path to the repository root.

    Returns:
        True if the module directory exists.
    """
    repo_path = Path(repo_root)
    modules_dir = repo_path / "modules" / "local"

    # Walk all module directories looking for the module
    for category_dir in modules_dir.iterdir():
        if category_dir.is_dir():
            for module_dir in category_dir.iterdir():
                if module_dir.is_dir():
                    main_file = module_dir / "main.nf"
                    if main_file.exists():
                        content = main_file.read_text()
                        # Check if this file defines the process
                        if f"process {module_name}" in content:
                            return True

    return False