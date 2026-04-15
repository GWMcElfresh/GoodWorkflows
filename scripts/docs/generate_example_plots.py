from __future__ import annotations

import csv
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path

import matplotlib.pyplot as plt


ROOT = Path(__file__).resolve().parents[2]
FIXTURE_DIR = ROOT / "tests" / "fixtures" / "synthetic_trial_data"
OUTPUT_DIR = ROOT / "docs" / "assets" / "generated"


def ensure_synthetic_fixture_bundle() -> None:
    subject_table = FIXTURE_DIR / "subjectTable_TB.csv"
    if subject_table.exists():
        return

    FIXTURE_DIR.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "Rscript",
            str(ROOT / "tests" / "fixtures" / "simulate_trial_data.R"),
            "--output-dir",
            str(FIXTURE_DIR),
            "--target",
            "all",
            "--seed",
            "20260414",
        ],
        check=True,
    )


def read_csv_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def parse_matrix_market(path: Path) -> list[list[int]]:
    with path.open(encoding="utf-8") as handle:
        rows = [line.strip() for line in handle if line.strip()]

    data_rows = [row for row in rows if not row.startswith("%")]
    n_rows, n_cols, _ = map(int, data_rows[0].split())
    matrix = [[0 for _ in range(n_cols)] for _ in range(n_rows)]

    for entry in data_rows[1:]:
        row_index, col_index, value = map(int, entry.split())
        matrix[row_index - 1][col_index - 1] = value

    return matrix


def plot_immune_composition(metadata_rows: list[dict[str, str]]) -> None:
    sample_ids = sorted({row["cDNA_ID"] for row in metadata_rows})
    classes = ["TNK", "Myeloid", "B cell"]
    counts = {sample_id: Counter() for sample_id in sample_ids}

    for row in metadata_rows:
        counts[row["cDNA_ID"]][row["RIRA_Immune.cellclass"]] += 1

    bottoms = [0] * len(sample_ids)
    fig, ax = plt.subplots(figsize=(8, 4.5))
    palette = {"TNK": "#1b9e77", "Myeloid": "#d95f02", "B cell": "#7570b3"}

    for immune_class in classes:
        values = [counts[sample_id][immune_class] for sample_id in sample_ids]
        ax.bar(sample_ids, values, bottom=bottoms, label=immune_class, color=palette[immune_class])
        bottoms = [bottom + value for bottom, value in zip(bottoms, values)]

    ax.set_title("Synthetic immune-class composition by sample")
    ax.set_ylabel("Cell count")
    ax.set_xlabel("Sample")
    ax.legend(frameon=False, ncols=3)
    ax.spines[["top", "right"]].set_visible(False)
    fig.tight_layout()
    fig.savefig(OUTPUT_DIR / "synthetic-immune-composition.png", dpi=200)
    plt.close(fig)


def plot_subject_table_heatmap(subject_rows: list[dict[str, str]]) -> None:
    metric_columns = [
        "TNK_Fraction",
        "Myeloid_Fraction",
        "Activated_TCell_Fraction",
        "Neutrophil_Fraction",
    ]
    sample_ids = [row["cDNA_ID"] for row in subject_rows]
    matrix = [[float(row[column]) for column in metric_columns] for row in subject_rows]

    fig, ax = plt.subplots(figsize=(7, 3.5))
    image = ax.imshow(matrix, cmap="viridis", aspect="auto", vmin=0.0, vmax=1.0)
    ax.set_xticks(range(len(metric_columns)), metric_columns, rotation=25, ha="right")
    ax.set_yticks(range(len(sample_ids)), sample_ids)
    ax.set_title("Synthetic subject-level fraction summary")

    for row_index, row in enumerate(matrix):
        for col_index, value in enumerate(row):
            ax.text(col_index, row_index, f"{value:.2f}", ha="center", va="center", color="white", fontsize=8)

    fig.colorbar(image, ax=ax, fraction=0.046, pad=0.04, label="Fraction")
    fig.tight_layout()
    fig.savefig(OUTPUT_DIR / "synthetic-subject-table-heatmap.png", dpi=200)
    plt.close(fig)


def plot_counts_heatmap() -> None:
    counts_dir = FIXTURE_DIR / "sample_counts"
    genes = [line.strip() for line in (counts_dir / "features.tsv").read_text(encoding="utf-8").splitlines() if line.strip()]
    barcodes = [line.strip() for line in (counts_dir / "barcodes.tsv").read_text(encoding="utf-8").splitlines() if line.strip()]
    matrix = parse_matrix_market(counts_dir / "matrix.mtx")

    fig, ax = plt.subplots(figsize=(8, 4.5))
    image = ax.imshow(matrix, cmap="magma", aspect="auto")
    ax.set_xticks(range(len(barcodes)), barcodes, rotation=45, ha="right", fontsize=8)
    ax.set_yticks(range(len(genes)), genes)
    ax.set_title("Synthetic exported count matrix")
    ax.set_xlabel("Barcode")
    ax.set_ylabel("Gene")
    fig.colorbar(image, ax=ax, fraction=0.046, pad=0.04, label="Raw count")
    fig.tight_layout()
    fig.savefig(OUTPUT_DIR / "synthetic-count-matrix-heatmap.png", dpi=200)
    plt.close(fig)


def main() -> int:
    ensure_synthetic_fixture_bundle()
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    metadata_rows = read_csv_rows(FIXTURE_DIR / "sample_metadata.csv")
    subject_rows = read_csv_rows(FIXTURE_DIR / "subjectTable_TB.csv")

    plot_immune_composition(metadata_rows)
    plot_subject_table_heatmap(subject_rows)
    plot_counts_heatmap()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
