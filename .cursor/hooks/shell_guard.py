"""Cursor beforeShellExecution hook for GoodWorkflows shell commands.

It asks for confirmation on destructive commands and adds context for common
Nextflow verification commands. Advisory patterns stay lightweight.
"""

from __future__ import annotations

import json
import re
import sys


DESTRUCTIVE_PATTERNS = [
    r"\bgit\s+reset\s+--hard\b",
    r"\bgit\s+clean\s+-[^\s]*f",
    r"\brm\s+-rf\s+[/\\.]",
    r"\bRemove-Item\b.*\s-Recurse\b.*\s-Force\b",
    r"\bdel\s+/[FfQqSs]\b",
]


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        print("{}")
        return 0

    command = payload.get("command") or ""
    if any(re.search(pattern, command) for pattern in DESTRUCTIVE_PATTERNS):
        print(
            json.dumps(
                {
                    "permission": "ask",
                    "user_message": "This command can delete or irreversibly discard GoodWorkflows files. Please confirm before it runs.",
                    "agent_message": "A GoodWorkflows hook flagged this as a destructive shell command.",
                }
            )
        )
        return 0

    if "nextflow run" in command and "-stub-run" not in command:
        print(
            json.dumps(
                {
                    "permission": "allow",
                    "agent_message": "[goodworkflows-shell] This is a real Nextflow run, not a stub-run. Do not describe it as lightweight DSL2 validation.",
                }
            )
        )
        return 0

    print(json.dumps({"permission": "allow"}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
