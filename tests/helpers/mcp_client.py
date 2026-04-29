"""
MCP stdio client for testing the nextflow_workflows MCP server.

Spawns the Node.js MCP server as a subprocess and communicates via
the MCP JSON-RPC protocol over stdin/stdout.
"""

import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Dict, Optional


class McpClientError(Exception):
    """Raised when the MCP client encounters an error."""


class McpClient:
    """Client for communicating with an MCP server over stdio."""

    def __init__(self, repo_root: str, timeout: float = 30.0):
        """
        Initialize the MCP client.

        Args:
            repo_root: Path to the GoodWorkflows repository root.
            timeout: Timeout in seconds for tool calls.
        """
        self.repo_root = Path(repo_root).resolve()
        self.timeout = timeout
        self._process: Optional[subprocess.Popen] = None
        self._request_id = 0
        self._server_info: Dict[str, Any] = {}
        self._tools: list = []

    def start(self) -> None:
        """Build and start the MCP server process."""
        mcp_dir = self.repo_root / "mcp-server"

        # Build the server if needed
        build_dir = mcp_dir / "build"
        if not (build_dir / "index.js").exists():
            print("Building MCP server...", file=sys.stderr)
            result = subprocess.run(
                ["npm", "run", "build"],
                cwd=str(mcp_dir),
                capture_output=True,
                text=True,
                timeout=60,
            )
            if result.returncode != 0:
                raise McpClientError(
                    f"Failed to build MCP server:\n{result.stderr}"
                )

        # Start the server
        env = os.environ.copy()
        env["GOODWORKFLOWS_ROOT"] = str(self.repo_root)

        self._process = subprocess.Popen(
            ["node", str(build_dir / "index.js")],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=str(self.repo_root),
            env=env,
            text=True,
        )

        # Perform MCP initialization handshake
        self._initialize()

    def _initialize(self) -> None:
        """Perform the MCP initialization handshake."""
        # Send initialize request
        init_response = self._send_request("initialize", {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {
                "name": "mcp-test-client",
                "version": "1.0.0",
            },
        })
        self._server_info = init_response

        # Send initialized notification (no response expected)
        self._send_notification("notifications/initialized", {})

        # Discover available tools
        tools_response = self._send_request("tools/list", {})
        self._tools = tools_response.get("tools", [])

    def _send_request(self, method: str, params: dict) -> dict:
        """Send a JSON-RPC request and return the result."""
        self._request_id += 1
        request = {
            "jsonrpc": "2.0",
            "id": self._request_id,
            "method": method,
            "params": params,
        }
        return self._send_and_receive(request)

    def _send_notification(self, method: str, params: dict) -> None:
        """Send a JSON-RPC notification (no response expected)."""
        notification = {
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
        }
        self._write_message(notification)
        # Don't wait for response for notifications

    def _send_and_receive(self, message: dict) -> dict:
        """Send a message and wait for the response."""
        self._write_message(message)

        # Read response
        deadline = time.time() + self.timeout
        while time.time() < deadline:
            if self._process is None or self._process.stdout is None:
                raise McpClientError("Server process not running")

            line = self._process.stdout.readline()
            if not line:
                # Check if process has terminated
                if self._process.poll() is not None:
                    stderr_output = ""
                    if self._process.stderr:
                        stderr_output = self._process.stderr.read()
                    raise McpClientError(
                        f"Server process terminated unexpectedly (exit code {self._process.returncode}).\n"
                        f"Stderr: {stderr_output}"
                    )
                time.sleep(0.01)
                continue

            try:
                response = json.loads(line.strip())
            except json.JSONDecodeError:
                continue

            # Check if this is the response to our request
            if response.get("id") == message.get("id"):
                if "error" in response:
                    raise McpClientError(
                        f"MCP error: {response['error'].get('message', str(response['error']))}"
                    )
                return response.get("result", {})

        raise McpClientError(f"Timeout waiting for response to {message.get('method')}")

    def _write_message(self, message: dict) -> None:
        """Write a JSON-RPC message to the server's stdin."""
        if self._process is None or self._process.stdin is None:
            raise McpClientError("Server process not running")
        self._process.stdin.write(json.dumps(message) + "\n")
        self._process.stdin.flush()

    def call_tool(self, tool_name: str, arguments: Optional[dict] = None) -> dict:
        """
        Call an MCP tool and return the parsed result.

        Args:
            tool_name: Name of the tool to call.
            arguments: Tool arguments as a dict.

        Returns:
            Parsed JSON result from the tool.

        Raises:
            McpClientError: If the tool call fails.
        """
        if arguments is None:
            arguments = {}

        result = self._send_request("tools/call", {
            "name": tool_name,
            "arguments": arguments,
        })

        # MCP tool results come back as content array
        content = result.get("content", [])
        if not content:
            raise McpClientError(f"Tool '{tool_name}' returned no content")

        # The first content item should be text
        text = content[0].get("text", "")
        if not text:
            raise McpClientError(f"Tool '{tool_name}' returned empty text")

        try:
            return json.loads(text)
        except json.JSONDecodeError as e:
            raise McpClientError(
                f"Tool '{tool_name}' returned invalid JSON: {e}\nRaw: {text[:500]}"
            )

    def get_tools(self) -> list:
        """Return the list of available tools."""
        return self._tools

    def stop(self) -> None:
        """Stop the MCP server process."""
        if self._process:
            try:
                self._process.stdin.close()
                self._process.stdout.close()
                if self._process.stderr:
                    self._process.stderr.close()
                self._process.terminate()
                self._process.wait(timeout=5)
            except Exception:
                self._process.kill()
            self._process = None