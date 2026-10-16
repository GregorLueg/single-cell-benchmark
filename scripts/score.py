# /// script
# requires-python = ">=3.12"
# dependencies = ["polars>=1.30", "numpy", "scikit-learn", "igraph", "leidenalg", "h5py"]
# ///
"""Score every tool's output on a simulated data set against the Splat truth.

Usage: score.py <results/dataset> <data/dataset>

Writes <results/dataset>/quality.csv and prints it as markdown.
"""

import sys
from pathlib import Path

import h5py
import igraph as ig
import leidenalg
import numpy as np
import polars as pl
from sklearn.metrics import adjusted_rand_score, normalized_mutual_info_score, roc_auc_score, silhouette_score
from sklearn.neighbors import NearestNeighbors

K = 15
# a true marker counts as detectable if seen in this share of its own group
MIN_DETECTED = 0.1
MAX_CELLS = 50_000
results, data = Path(sys.argv[1]), Path(sys.argv[2])

cells = pl.read_csv(data / "cells_truth.tsv.gz", separator="\t").select("Cell", "Batch", "Group")
genes = pl.read_csv(data / "genes_truth.tsv.gz", separator="\t", infer_schema_length=None)
de_cols = [c for c in genes.columns if c.startswith("DEFacGroup")]
de_any = set(genes.filter(pl.any_horizontal(pl.col(c) != 1 for c in de_cols))["Gene"])
rarest = cells.group_by("Group").len().sort("len")["Group"][0]


def group_detection() -> dict[str, set]:
    """Genes detected in >= MIN_DETECTED of each group's cells, from the raw
    counts in DGE.h5ad, streamed in row blocks. Rows follow cells_truth."""
    groups = cells["Group"].to_numpy()
    names, codes = np.unique(groups, return_inverse=True)
    with h5py.File(data / "DGE.h5ad") as f:
        x = f["X"]
        n_genes = int(x.attrs["shape"][1])
        gene_names = f["var"][f["var"].attrs["_index"]][:].astype(str)
        indptr = x["indptr"][:]
        hits = np.zeros(len(names) * n_genes, dtype=np.int64)
        for lo in range(0, len(indptr) - 1, 100_000):
            hi = min(lo + 100_000, len(indptr) - 1)
            idx = x["indices"][indptr[lo]:indptr[hi]]
            row_grp = np.repeat(codes[lo:hi], np.diff(indptr[lo:hi + 1]))
            hits += np.bincount(row_grp * n_genes + idx, minlength=hits.size)
    frac = hits.reshape(len(names), n_genes) / np.bincount(codes)[:, None]
    return {g: set(gene_names[frac[i] >= MIN_DETECTED]) for i, g in enumerate(names)}


detectable = group_detection()


def first_col_as_cell(df: pl.DataFrame) -> pl.DataFrame:
    return df.rename({df.columns[0]: "Cell"}).with_columns(pl.col("Cell").cast(pl.String))


def knn(x: np.ndarray) -> np.ndarray:
    _, idx = NearestNeighbors(n_neighbors=K + 1).fit(x).kneighbors(x)
    return idx[:, 1:]


def entropy(labels: np.ndarray) -> float:
    _, n = np.unique(labels, return_counts=True)
    p = n / n.sum()
    return float(-(p * np.log(p)).sum())


def group_f1(cl: pl.DataFrame, lab: str) -> pl.DataFrame:
    """Per true group, F1 of its best-matching cluster."""
    n = cl.group_by("Group", lab).len("n")
    return (
        n.join(cl.group_by("Group").len("n_group"), on="Group")
        .join(cl.group_by(lab).len("n_cluster"), on=lab)
        .with_columns(f1=2 * pl.col("n") / (pl.col("n_group") + pl.col("n_cluster")))
        .group_by("Group")
        .agg(pl.col("f1").max())
    )


def embedding_scores(path: Path, name: str, full: bool) -> dict:
    emb = first_col_as_cell(pl.read_csv(path)).join(cells, on="Cell")
    if emb.height > MAX_CELLS:
        emb = emb.sample(MAX_CELLS, seed=42)
    x = emb.drop("Cell", "Batch", "Group").to_numpy()
    group, batch = emb["Group"].to_numpy(), emb["Batch"].to_numpy()
    nn = knn(x)
    same = group[nn] == group[:, None]
    out = {
        f"{name}_knn_purity": float(same.mean()),
        f"{name}_knn_purity_rarest": float(same[group == rarest].mean()),
    }
    if not full:
        return out
    # batch entropy among neighbours, relative to that of K random cells of
    # the same group: 1 is perfect mixing given the uneven composition
    rng = np.random.default_rng(42)
    expected = {
        g: np.mean([entropy(rng.choice(batch[group == g], K, replace=False)) for _ in range(200)])
        for g in np.unique(group)
        if (group == g).sum() > K
    }
    mix = [entropy(batch[nn[i]]) / expected[group[i]] for i in range(len(group)) if expected.get(group[i], 0) > 0]
    edges = [(i, j) for i in range(len(nn)) for j in nn[i] if i < j]
    g = ig.Graph(n=len(nn), edges=edges)
    probe = leidenalg.find_partition(g, leidenalg.RBConfigurationVertexPartition, resolution_parameter=1.0, seed=42)
    return out | {
        f"{name}_asw_group": float(silhouette_score(x, group, sample_size=min(len(x), 10_000), random_state=42)),
        f"{name}_batch_mix": float(np.mean(mix)),
        f"{name}_probe_ari": adjusted_rand_score(group, probe.membership),
    }


def rank_scores(s: pl.DataFrame) -> tuple[float, float]:
    # R-precision: precision in the top n, n = number of true markers
    top = s.sort("score", descending=True).head(int(s["de"].sum()))
    return roc_auc_score(s["de"], s["score"]), top["de"].mean()


def dge_scores(m: pl.DataFrame, shared: dict[str, set]) -> dict:
    """Up-regulated markers only, as bixverse tests one-sided by default. On
    all genes, genes a tool filtered out rank last, so its thresholds count;
    on the genes every tool reported, only the ranking does. The _det
    variants only count markers detectable in their own group as true, so a
    filter dropping genes nobody could use as markers is not penalised."""
    out = {k: [] for k in ["auroc", "rprec", "reported", "true_reported", "auroc_shared", "rprec_shared",
                           "auroc_det", "rprec_det", "true_reported_det"]}
    for k, col in enumerate(de_cols, start=1):
        g = f"Group{k}"
        s = genes.select("Gene", (pl.col(col) > 1).alias("de")).join(
            m.filter(pl.col("group") == g).select(pl.col("gene").alias("Gene"), "score"), on="Gene", how="left"
        ).with_columns(pl.col("score").fill_nan(None))
        hit = s.filter(pl.col("score").is_not_null())
        out["reported"].append(hit.height)
        out["true_reported"].append(hit["de"].sum())
        out["true_reported_det"].append(hit.filter(pl.col("de") & pl.col("Gene").is_in(detectable[g])).height)
        det = s.with_columns(pl.col("de") & pl.col("Gene").is_in(detectable[g]))
        for suffix, d in [("", s.with_columns(pl.col("score").fill_null(-1e300))),
                          ("_shared", hit.filter(pl.col("Gene").is_in(shared[g]))),
                          ("_det", det.with_columns(pl.col("score").fill_null(-1e300)))]:
            auc, rprec = rank_scores(d)
            out["auroc" + suffix].append(auc)
            out["rprec" + suffix].append(rprec)
    return {f"dge_{k}": float(np.mean(v)) for k, v in out.items()}


tools = sorted(p for p in results.iterdir() if (p / "clusters.csv").exists())
markers = {
    t.name: pl.read_csv(t / "markers.csv", schema_overrides={"group": pl.String, "gene": pl.String, "score": pl.Float64})
    .filter(pl.col("score").is_not_null() & pl.col("score").is_not_nan())
    for t in tools
    if (t / "markers.csv").exists()
}
shared = {
    f"Group{k}": set.intersection(*(set(m.filter(pl.col("group") == f"Group{k}")["gene"]) for m in markers.values()))
    for k in range(1, len(de_cols) + 1)
} if markers else {}

rows = []
for tool in tools:
    row = {"tool": tool.name}
    cl = first_col_as_cell(pl.read_csv(tool / "clusters.csv")).join(cells, on="Cell")
    lab = cl[cl.columns[1]].cast(pl.String)
    row |= {
        "cells": cl.height,
        "n_clusters": lab.n_unique(),
        "ari": adjusted_rand_score(cl["Group"], lab),
        "nmi": normalized_mutual_info_score(cl["Group"], lab),
        "ari_batch": adjusted_rand_score(cl["Batch"], lab),
    }
    f1 = group_f1(cl.with_columns(lab), cl.columns[1])
    row |= {
        "f1_mean": f1["f1"].mean(),
        "f1_min": f1["f1"].min(),
        "f1_rarest": f1.filter(pl.col("Group") == rarest)["f1"][0],
    }
    if (tool / "hvg.csv").exists():
        hvg = set(pl.read_csv(tool / "hvg.csv")["gene"].cast(pl.String))
        row |= {"hvg_precision": len(hvg & de_any) / len(hvg)}
    for name in ["pca", "harmony", "umap", "tsne", "tsne_quick"]:
        if (tool / f"emb_{name}.csv.gz").exists():
            row |= embedding_scores(tool / f"emb_{name}.csv.gz", name, full=name in ("pca", "harmony"))
    if tool.name in markers:
        row |= dge_scores(markers[tool.name], shared)
    rows.append(row)

df = pl.DataFrame(rows).with_columns(pl.selectors.float().round(3))
df.write_csv(results / "quality.csv")
with pl.Config(tbl_formatting="MARKDOWN", tbl_hide_column_data_types=True, tbl_hide_dataframe_shape=True,
               tbl_cols=-1, tbl_rows=-1, tbl_width_chars=1000):
    print(df.transpose(include_header=True, header_name="metric", column_names="tool"))
