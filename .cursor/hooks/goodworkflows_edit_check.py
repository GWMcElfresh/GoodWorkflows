"""Cursor afterFileEdit hook for GoodWorkflows-specific edit risks.

Advisory only: it returns additional context and never blocks edits.
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


def get_file_path(payload: dict) -> Path | None:
    raw = payload.get("filePath") or payload.get("file_path") or payload.get("path")
    return Path(raw) if raw else None


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return ""


def check_nextflow(path: Path, text: str) -> list[str]:
    issues: list[str] = []
    if path.suffix == ".nf":
        if re.search(r"(?m)^\s*switch\s*\(", text):
            issues.append("workflow bodies cannot use `switch`; use `if/else if/else`.")
        if re.search(r'container\s+"[$][{]params\.', text):
            issues.append("module container directives should use `container { params.x }`.")
        if re.search(r"(?m)^\s*(tag|publishDir)\b.*[$][{]meta\.", text):
            issues.append("`tag`/`publishDir` must not interpolate input variables like `${meta.id}`.")
        process_count = len(re.findall(r"(?m)^\s*process\s+\w+\s*\{", text))
        stub_count = len(re.findall(r"(?m)^\s*stub\s*:", text))
        if process_count and stub_count < process_count:
            issues.append("every process should have a `stub:` block for CI stub-runs.")
    if path.suffix == ".config":
        if re.search(r"(?m)^\s*def\s+\w+", text):
            issues.append("avoid top-level `def` declarations in config files.")
        if re.search(r"container\s*=\s*\{\s*params\.", text):
            issues.append("avoid config-level `container = { params.x }`; use module-level closures.")
    return issues


def check_template(path: Path, text: str) -> list[str]:
    if "modules" not in path.parts or "templates" not in path.parts:
        return []
    issues: list[str] = []
    if path.suffix.lower() in {".r", ".py", ".sh"}:
        if re.search(r"(?<!\\)\$(?!\{)", text):
            issues.append("template contains bare `$`; escape as `\\$` unless it is intentional.")
    if path.suffix == ".py":
        if re.search(r"(?<!\\)\\[ntr]", text):
            issues.append("Python template contains raw backslash escapes; verify Groovy rendering.")
        if ("scanpy" in text or "umap" in text or "pynndescent" in text) and "NUMBA_CACHE_DIR" not in text:
            issues.append("templates importing scanpy/umap should set `NUMBA_CACHE_DIR=/tmp` before imports.")
    return issues


def main() -> int:
    path = get_file_path(load_payload())
    if path is None or not path.is_file():
        print("{}")
        return 0

    text = read_text(path)
    issues = check_nextflow(path, text) + check_template(path, text)
    if not issues:
        print("{}")
        return 0

    message = "[goodworkflows-edit-check]\n" + "\n".join(f"- {issue}" for issue in issues)
    print(json.dumps({"additional_context": message}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
