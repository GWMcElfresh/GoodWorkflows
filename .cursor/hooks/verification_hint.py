"""Cursor stop hook that suggests GoodWorkflows verification from git diff.

This does not run heavy tests. It emits concise advisory context when changed
files imply a likely verification path, including host-aware test entrypoint hints.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

VALID_TEST_HOSTS = frozenset({"wsl", "mac", "bazzite"})


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


def resolve_test_host(repo: Path) -> tuple[str, str]:
    """Return (host_id, default_tier) using host_profile.sh when available."""
    local_override = repo / "template" / "gw" / ".test-host"
    if local_override.is_file():
        for line in local_override.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line.startswith("export GW_TEST_HOST="):
                host = line.split("=", 1)[1].strip().strip('"').strip("'")
                if host:
                    return host, _default_tier_for(host)

    if os.environ.get("GW_TEST_HOST"):
        host = os.environ["GW_TEST_HOST"]
        return host, _default_tier_for(host)

    profile_sh = repo / "scripts" / "test" / "lib" / "host_profile.sh"
    if profile_sh.is_file():
        try:
            proc = subprocess.run(
                [
                    "bash",
                    "-c",
                    f'source "{profile_sh}" && GW_REPO_ROOT="{repo}" && '
                    "resolve_test_host auto && echo \"${GW_RESOLVED_HOST}\" && "
                    "host_default_tier \"${GW_RESOLVED_HOST}\"",
                ],
                cwd=repo,
                capture_output=True,
                text=True,
                timeout=15,
                check=False,
            )
            lines = [ln.strip() for ln in proc.stdout.splitlines() if ln.strip()]
            if len(lines) >= 2 and lines[0] in VALID_TEST_HOSTS:
                return lines[0], lines[1]
            if len(lines) == 1 and lines[0] in VALID_TEST_HOSTS:
                return lines[0], _default_tier_for(lines[0])
        except (FileNotFoundError, subprocess.TimeoutExpired):
            pass

    import platform

    if platform.system() == "Darwin":
        return "mac", "stub"
    return "wsl", "light"


def _default_tier_for(host: str) -> str:
    return {"wsl": "light", "mac": "stub", "bazzite": "stub"}.get(host, "light")


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


def host_test_hints(repo: Path) -> list[str]:
    host, default_tier = resolve_test_host(repo)
    lines = [
        f"Resolved host: {host} (default tier: {default_tier})",
        "Run: bash scripts/test/run_host_tests.sh --affected",
    ]
    if default_tier == "light":
        lines.append("Full serial stub: bash scripts/test/run_host_tests.sh --tier stub")
    if host == "mac":
        lines.append("CPU real run: bash scripts/test/run_host_tests.sh --tier real --workflow ingest_export")
    if host == "bazzite":
        lines.append("GPU real run: bash scripts/test/run_host_tests.sh --tier real --workflow integration")
    return lines


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
    host_lines = host_test_hints(repo)

    if not suggested and not host_lines:
        print("{}")
        return 0

    parts: list[str] = []
    if suggested:
        parts.append("[goodworkflows-verify]\n" + "\n".join(f"- {item}" for item in suggested))
    if host_lines:
        parts.append("[goodworkflows-host-test]\n" + "\n".join(f"- {item}" for item in host_lines))

    message = "\n\n".join(parts)
    print(json.dumps({"additional_context": message}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
