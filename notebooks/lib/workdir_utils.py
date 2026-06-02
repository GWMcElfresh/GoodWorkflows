"""Helpers for inspecting Nextflow work directories from notebooks."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


@dataclass(frozen=True)
class TaskWorkDir:
    path: Path
    exitcode: int | None
    mtime: float
    tag: str | None

    @property
    def failed(self) -> bool:
        return self.exitcode is not None and self.exitcode != 0


def resolve_path(path: str | Path) -> Path:
    return Path(path).expanduser().resolve()


def find_repo_root(start: str | Path | None = None, max_hops: int = 8) -> Path:
    """Walk parents from start (or cwd) until main.nf is found."""
    cur = resolve_path(start or Path.cwd())
    for _ in range(max_hops):
        if (cur / "main.nf").is_file():
            return cur
        parent = cur.parent
        if parent == cur:
            break
        cur = parent
    raise FileNotFoundError(
        "Could not locate GoodWorkflows repo root (main.nf). "
        "Open the notebook with cwd set to the repo, notebooks/, or examples/."
    )


def validate_run_layout(run_dir: str | Path) -> dict[str, Path]:
    """Resolve run_dir and ensure work/, logs/, outputs/ exist or are creatable parents."""
    run = resolve_path(run_dir)
    work = run / "work"
    logs = run / "logs"
    outputs = run / "outputs"
    log_file = logs / "nextflow.log"

    missing = [p for p in (work,) if not p.is_dir()]
    if missing:
        raise FileNotFoundError(
            f"Work directory not found: {work}\n"
            "Set RUN_DIR to a GoodWorkflows run folder (e.g. template/gw/runs/latest)."
        )

    return {
        "run_dir": run,
        "work_dir": work,
        "logs_dir": logs,
        "outputs_dir": outputs,
        "log_file": log_file,
    }


def _read_exitcode(task_dir: Path) -> int | None:
    exit_file = task_dir / ".exitcode"
    if not exit_file.is_file():
        return None
    try:
        return int(exit_file.read_text().strip())
    except ValueError:
        return None


def _read_tag(task_dir: Path) -> str | None:
    begin = task_dir / ".command.begin"
    if begin.is_file():
        text = begin.read_text(errors="replace").strip()
        if text:
            return text.splitlines()[0][:200]
    name = task_dir.name
    if name and name != ".":
        return name
    return None


def list_task_dirs(work_dir: str | Path) -> list[TaskWorkDir]:
    """List hash work directories under work/, newest first."""
    root = resolve_path(work_dir)
    tasks: list[TaskWorkDir] = []
    for entry in root.iterdir():
        if not entry.is_dir() or entry.name.startswith("."):
            continue
        tasks.append(
            TaskWorkDir(
                path=entry,
                exitcode=_read_exitcode(entry),
                mtime=entry.stat().st_mtime,
                tag=_read_tag(entry),
            )
        )
    tasks.sort(key=lambda t: t.mtime, reverse=True)
    return tasks


def failed_tasks(tasks: Iterable[TaskWorkDir]) -> list[TaskWorkDir]:
    return [t for t in tasks if t.failed]


def command_artifacts(task_dir: str | Path) -> dict[str, Path | None]:
    base = resolve_path(task_dir)
    names = (
        ".command.sh",
        ".command.err",
        ".command.out",
        ".command.log",
        ".exitcode",
        ".command.begin",
    )
    return {name: (base / name if (base / name).is_file() else None) for name in names}


def tail_file(path: Path | None, n: int = 80) -> str:
    if path is None or not path.is_file():
        return "(file not found)"
    lines = path.read_text(errors="replace").splitlines()
    if len(lines) <= n:
        return "\n".join(lines)
    return "\n".join(lines[-n:])


def peek_file(path: Path | None, n: int = 60) -> str:
    if path is None or not path.is_file():
        return "(file not found)"
    lines = path.read_text(errors="replace").splitlines()
    return "\n".join(lines[:n])


def list_outputs_tree(outputs_dir: str | Path, max_depth: int = 4) -> list[str]:
    """Return relative paths under outputs/ for quick browsing."""
    root = resolve_path(outputs_dir)
    if not root.is_dir():
        return []
    lines: list[str] = []

    def walk(current: Path, depth: int) -> None:
        if depth > max_depth:
            return
        try:
            children = sorted(current.iterdir(), key=lambda p: (not p.is_dir(), p.name.lower()))
        except OSError:
            return
        for child in children:
            rel = child.relative_to(root)
            lines.append(str(rel) + ("/" if child.is_dir() else ""))
            if child.is_dir():
                walk(child, depth + 1)

    walk(root, 0)
    return lines


def find_staged_data_files(task_dir: str | Path, suffixes: tuple[str, ...] = (".h5ad", ".rds")) -> list[Path]:
    base = resolve_path(task_dir)
    found: list[Path] = []
    for root, _dirs, files in os.walk(base):
        for name in files:
            if name.endswith(suffixes):
                found.append(Path(root) / name)
    return sorted(found)
