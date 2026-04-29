"""
Shared pytest fixtures for MCP server tests.

Provides:
- mcp_client: Session-scoped MCP client connected to the real server
- repo_root: Path to the GoodWorkflows repository
- Various samplesheet fixtures
- Temporary work directory for Nextflow runs
"""

import os
import tempfile
from pathlib import Path
from typing import Generator

import pytest

# Add helpers to path
import sys
sys.path.insert(0, str(Path(__file__).parent))

from helpers.mcp_client import McpClient, McpClientError


# ---------------------------------------------------------------------------
# Repository root
# ---------------------------------------------------------------------------

@pytest.fixture(scope="session")
def repo_root() -> Path:
    """Path to the GoodWorkflows repository root."""
    root = Path(__file__).parent.parent.resolve()
    return root


# ---------------------------------------------------------------------------
# MCP Client (session-scoped — one server instance for all tests)
# ---------------------------------------------------------------------------

@pytest.fixture(scope="session")
def mcp_client(repo_root: Path) -> Generator[McpClient, None, None]:
    """
    Start the MCP server and return a connected client.

    Session-scoped: the server is started once and reused across all tests.
    """
    client = McpClient(str(repo_root), timeout=30.0)
    try:
        client.start()
        yield client
    finally:
        client.stop()


# ---------------------------------------------------------------------------
# Temporary directories
# ---------------------------------------------------------------------------

@pytest.fixture(scope="function")
def temp_work_dir() -> Generator[Path, None, None]:
    """Temporary Nextflow work directory."""
    with tempfile.TemporaryDirectory(prefix="nf_work_") as tmpdir:
        yield Path(tmpdir)


@pytest.fixture(scope="function")
def temp_output_dir() -> Generator[Path, None, None]:
    """Temporary output directory for generated files."""
    with tempfile.TemporaryDirectory(prefix="nf_output_") as tmpdir:
        yield Path(tmpdir)


# ---------------------------------------------------------------------------
# Samplesheet fixtures
# ---------------------------------------------------------------------------

@pytest.fixture(scope="session")
def fixtures_dir(repo_root: Path) -> Path:
    """Path to the test fixtures directory."""
    return repo_root / "tests" / "fixtures"


@pytest.fixture(scope="session")
def valid_samplesheet(fixtures_dir: Path) -> str:
    """Path to a valid 3-species samplesheet."""
    return str(fixtures_dir / "samplesheet_valid.csv")


@pytest.fixture(scope="session")
def single_species_samplesheet(fixtures_dir: Path) -> str:
    """Path to a single-species samplesheet."""
    return str(fixtures_dir / "samplesheet_single_species.csv")


@pytest.fixture(scope="session")
def missing_cols_samplesheet(fixtures_dir: Path) -> str:
    """Path to a samplesheet with missing required columns."""
    return str(fixtures_dir / "samplesheet_missing_cols.csv")


@pytest.fixture(scope="session")
def empty_samplesheet(fixtures_dir: Path) -> str:
    """Path to an empty samplesheet (header only)."""
    return str(fixtures_dir / "samplesheet_empty.csv")


@pytest.fixture(scope="session")
def real_samplesheet(repo_root: Path) -> str:
    """Path to the real data samplesheet."""
    return str(repo_root / "data" / "samplesheet.csv")


# ---------------------------------------------------------------------------
# Helper to skip tests if MCP server is unavailable
# ---------------------------------------------------------------------------

def require_mcp_server():
    """Decorator-like check: skip test if MCP server can't start."""
    # This is checked at fixture time, so tests that depend on mcp_client
    # will naturally fail with a clear error if the server can't start.
    pass