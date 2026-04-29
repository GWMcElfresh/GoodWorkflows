"""
Tests for the DSL2 workflow validator.

Validates that generated workflows are syntactically valid DSL2
and follow GoodWorkflows conventions.
"""

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from helpers.dsl2_validator import validate_dsl2_workflow


class TestDsl2Validator:
    """Validate DSL2 workflow syntax checking."""

    def test_valid_workflow_passes(self):
        """A well-formed workflow should pass validation."""
        content = """#!/usr/bin/env nextflow

include { INGEST } from '../modules/local/rdiscvr/ingest/main.nf'

workflow TEST {
    take:
    input_ch

    main:
    INGEST(input_ch)

    emit:
    rds = INGEST.out.rds
}
"""
        is_valid, issues = validate_dsl2_workflow(content, str(Path(__file__).parent.parent.parent))
        assert is_valid, f"Expected valid, got issues: {issues}"

    def test_missing_shebang_fails(self):
        """Missing shebang should be flagged."""
        content = """
workflow TEST {
    main:
}
"""
        is_valid, issues = validate_dsl2_workflow(content, str(Path(__file__).parent.parent.parent))
        assert not is_valid
        assert any("shebang" in i.lower() for i in issues)

    def test_missing_take_section_fails(self):
        """Missing take: section should be flagged."""
        content = """#!/usr/bin/env nextflow

workflow TEST {
    main:
    emit:
}
"""
        is_valid, issues = validate_dsl2_workflow(content, str(Path(__file__).parent.parent.parent))
        assert not is_valid
        assert any("take" in i.lower() for i in issues)

    def test_missing_main_section_fails(self):
        """Missing main: section should be flagged."""
        content = """#!/usr/bin/env nextflow

workflow TEST {
    take:
    emit:
}
"""
        is_valid, issues = validate_dsl2_workflow(content, str(Path(__file__).parent.parent.parent))
        assert not is_valid
        assert any("main" in i.lower() for i in issues)

    def test_missing_emit_section_fails(self):
        """Missing emit: section should be flagged."""
        content = """#!/usr/bin/env nextflow

workflow TEST {
    take:
    main:
}
"""
        is_valid, issues = validate_dsl2_workflow(content, str(Path(__file__).parent.parent.parent))
        assert not is_valid
        assert any("emit" in i.lower() for i in issues)

    def test_unbalanced_braces_fails(self):
        """Unbalanced braces should be flagged."""
        content = """#!/usr/bin/env nextflow

workflow TEST {
    take:
    main:
    emit:
"""
        is_valid, issues = validate_dsl2_workflow(content, str(Path(__file__).parent.parent.parent))
        assert not is_valid
        assert any("brace" in i.lower() for i in issues)

    def test_nonexistent_include_fails(self):
        """Include of nonexistent file should be flagged."""
        content = """#!/usr/bin/env nextflow

include { FAKE_MODULE } from '../modules/local/nonexistent/main.nf'

workflow TEST {
    take:
    main:
    emit:
}
"""
        is_valid, issues = validate_dsl2_workflow(content, str(Path(__file__).parent.parent.parent))
        assert not is_valid
        assert any("does not exist" in i for i in issues)

    def test_collect_without_collect_call_fails(self):
        """Using _collected channel without .collect() should be flagged."""
        content = """#!/usr/bin/env nextflow

workflow TEST {
    take:
    input_ch

    main:
    // Missing: ch_collected = input_ch.collect()
    SOME_PROCESS(input_ch_collected)

    emit:
}
"""
        is_valid, issues = validate_dsl2_workflow(content, str(Path(__file__).parent.parent.parent))
        assert not is_valid
        assert any("collect" in i.lower() for i in issues)