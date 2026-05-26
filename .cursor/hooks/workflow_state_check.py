"""Advisory Cursor hook for active GoodWorkflows lifecycle state.

Reads workflow-state.yaml and reminds agents about the active stage before edits.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


def load_payload() -> dict:
    try:
        return json.load(sys.stdin)
    except json.JSONDecodeError:
        return {}


def repo_root(start: Path) -> Path | None:
    for candidate in [start, *start.parents]:
        if (candidate / ".git").is_dir():
            return candidate
    return None


def read_state_summary(repo: Path) -> str | None:
    state = repo / "workflow-state.yaml"
    if not state.is_file():
        return None
    try:
        text = state.read_text(encoding="utf-8")
    except OSError:
        return None

    stage = re.search(r'(?m)^current_stage:\s*"?([^"\n]+)"?', text)
    status = re.search(r"(?m)^overall_status:\s*([^\n]+)", text)
    active = re.search(r"(?m)^active_cycle:\s*([^\n]+)", text)
    parts = []
    if stage:
        parts.append(f"stage={stage.group(1).strip()}")
    if status:
        parts.append(f"status={status.group(1).strip()}")
    if active:
        parts.append(f"cycle={active.group(1).strip()}")
    return ", ".join(parts) if parts else None


def main() -> int:
    payload = load_payload()
    raw = payload.get("filePath") or payload.get("file_path") or payload.get("path") or "."
    path = Path(raw)
    root = repo_root(path if path.is_dir() else path.parent)
    if root is None:
        print("{}")
        return 0

    summary = read_state_summary(root)
    if not summary:
        print("{}")
        return 0

    print(
        json.dumps(
            {
                "additional_context": (
                    f"[goodworkflows-state] Active lifecycle: {summary}. "
                    "Keep edits aligned with the active numbered stage and update state through goodworkflows-state-manager."
                )
            }
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
