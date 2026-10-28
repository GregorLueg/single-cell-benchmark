# /// script
# requires-python = ">=3.12"
# dependencies = ["polars>=1.30", "numpy", "scikit-learn", "scipy"]
# ///
"""Score every tool's embeddings on a Tahoe run against cell_line, and compare
the DGE results between tools (there is no DGE truth).

Usage: score.py <tahoe/results/dataset>

Writes quality.csv and dge_agreement.csv into it and prints both as markdown.
"""

import sys
from itertools import combinations
from pathlib import Path

import numpy as np
import polars as pl
from scipy.stats import spearmanr
from sklearn.metrics import silhouette_score
from sklearn.neighbors import NearestNeighbors

K = 15
MAX_CELLS = 50_000
results = Path(sys.argv[1])


def entropy(labels: np.ndarray) -> float:
    _, n = np.unique(labels, return_counts=True)
    p = n / n.sum()
    return float(-(p * np.log(p)).sum())


def embedding_scores(x: np.ndarray, truth: np.ndarray, batch: np.ndarray, name: str) -> dict:
    _, nn = NearestNeighbors(n_neighbors=K + 1).fit(x).kneighbors(x)
    nn = nn[:, 1:]
    # batch entropy among neighbours, relative to that of K random cells of
    # the same cell line: 1 is perfect mixing given the uneven composition
    rng = np.random.default_rng(42)
    expected = {
        g: np.mean([entropy(rng.choice(batch[truth == g], K, replace=False)) for _ in range(200)])
        for g in np.unique(truth)
        if (truth == g).sum() > K
    }
    mix = [entropy(batch[nn[i]]) / expected[truth[i]] for i in range(len(truth)) if expected.get(truth[i], 0) > 0]
    return {
        f"{name}_knn_purity": float((truth[nn] == truth[:, None]).mean()),
        f"{name}_batch_mix": float(np.mean(mix)),
        f"{name}_asw_truth": float(silhouette_score(x, truth, sample_size=10_000, random_state=42)),
    }


# each tool's markers as gene -> log fold change, Gemcitabine over DMSO_TF;
# CyteArc reports group means, so its fold change is taken from those
def lfc(tool: Path) -> pl.DataFrame:
    m = pl.read_csv(tool / "markers.csv", infer_schema_length=None)
    match tool.name.split("_csc")[0]:
        case "bixverse":
            m = m.select(gene="gene_id", lfc="lfc")
        case "scanpy_dask":
            m = m.select(gene="names", lfc="logfoldchanges")
        case "seurat_bpcells":
            m = m.select(gene="gene", lfc="avg_log2FC")
        case "cytearc":
            m = m.select(gene="feature_name", lfc=((pl.col("mean") + 1e-9) / (pl.col("mean_rest") + 1e-9)).log(2))
    return m.filter(pl.col("lfc").is_finite())


tools = sorted(p for p in results.iterdir() if (p / "score_cells.csv.gz").exists())
rows = []
for tool in tools:
    # rows of score_cells and the emb_* files are the same cells in the same order
    cells = pl.read_csv(tool / "score_cells.csv.gz", schema_overrides={"truth": pl.String, "batch": pl.String})
    rng = np.random.default_rng(42)
    idx = np.sort(rng.choice(cells.height, min(cells.height, MAX_CELLS), replace=False))
    truth, batch = cells["truth"].to_numpy()[idx], cells["batch"].to_numpy()[idx]
    row = {"tool": tool.name, "cells_scored": len(idx)}
    for name in ["harmony", "umap"]:
        x = pl.read_csv(tool / f"emb_{name}.csv.gz").to_numpy()[idx]
        row |= embedding_scores(x, truth, batch, name)
    rows.append(row)

lfcs = {t.name: lfc(t) for t in tools if (t / "markers.csv").exists()}
agree = []
for a, b in combinations(lfcs, 2):
    j = lfcs[a].join(lfcs[b], on="gene", suffix="_b")
    # CyteArc reports genes no cell expresses, with a fold change of exactly 0
    both = j.filter((pl.col("lfc") != 0) & (pl.col("lfc_b") != 0))
    agree.append({
        "tool_a": a,
        "tool_b": b,
        "shared_genes": j.height,
        "lfc_spearman": float(spearmanr(j["lfc"], j["lfc_b"]).statistic),
        "sign_agreement": float((np.sign(both["lfc"]) == np.sign(both["lfc_b"])).mean()),
    })

quality = pl.DataFrame(rows).with_columns(pl.selectors.float().round(3))
dge = pl.DataFrame(agree).with_columns(pl.selectors.float().round(3))
quality.write_csv(results / "quality.csv")
dge.write_csv(results / "dge_agreement.csv")
with pl.Config(tbl_formatting="MARKDOWN", tbl_hide_column_data_types=True, tbl_hide_dataframe_shape=True,
               tbl_cols=-1, tbl_rows=-1, tbl_width_chars=1000):
    print(quality.transpose(include_header=True, header_name="metric", column_names="tool"))
    print(dge)
