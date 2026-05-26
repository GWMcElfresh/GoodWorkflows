"""Cursor stop hook that suggests GoodWorkflows verification from git diff.

This does not run heavy tests. It emits concise advisory context when changed
files imply a likely verification path.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


def repo_root() -> Path | None:
    cwd = Path.cwd()
    for candidate in [cwd, *cwd.parents]:
        if (candidate / ".git").is_dir():
            return candidate
    return None


def changed_files(repo: Path) -> list[str]:
    try:
        proc = subprocess.run(
            ["git", "diff", "--name-only", "HEAD"],
            cwd=repo,
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return []
    return [line.strip() for line in proc.stdout.splitlines() if line.strip()]


def hints(files: list[str]) -> list[str]:
    result: list[str] = []
    if any(path.endswith((".nf", ".config")) for path in files):
        result.append("run affected Nextflow workflow/module with `-profile test -stub-run`.")
    if any(path.endswith(".sh") for path in files):
        result.append("run ShellCheck if available, otherwise `bash -n` on changed shell scripts.")
    if any(path.startswith("modules/local/") and "/templates/" in path for path in files):
        result.append("inspect rendered template risks and pair syntax review with an affected stub-run.")
    if any(path.startswith("template/") or path == "scripts/image-manifest.txt" for path in files):
        result.append("check workflow list and container image parity across local/cluster/CI files.")
    if any(path.startswith("docs/") or path in {"mkdocs.yml", "README.md"} for path in files):
        result.append("run docs generation/build checks if docs tooling is available.")
    return result


def main() -> int:
    try:
        json.load(sys.stdin)
    except json.JSONDecodeError:
        pass

    repo = repo_root()
    if repo is None:
        print("{}")
        return 0

    suggested = hints(changed_files(repo))
    if not suggested:
        print("{}")
        return 0

    message = "[goodworkflows-verify]\n" + "\n".join(f"- {item}" for item in suggested)
    print(json.dumps({"additional_context": message}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
