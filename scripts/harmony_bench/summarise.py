# /// script
# requires-python = ">=3.12"
# dependencies = ["polars>=1.30", "numpy", "scikit-learn"]
# ///
"""Timing, memory and output agreement for the same-input Harmony benchmark.
Quality metrics come from score.py on per-implementation dirs (see stage()).
Usage: summarise.py stage | report"""

import gzip
import shutil
import sys
from pathlib import Path

import numpy as np
import polars as pl
from sklearn.neighbors import NearestNeighbors

R = Path(__file__).resolve().parents[2] / "results/harmony_bench"
IMPLS = ["v1", "v2", "v2_b05", "gpu", "mlx", "harmonypy"]


def stage():
    # score.py wants one dir per tool with clusters.csv; the clusters are a dummy
    for ds in ["splat_100k", "splat_1m"]:
        for impl in IMPLS + ["input"]:
            d = R / f"score_{ds}" / impl
            d.mkdir(parents=True, exist_ok=True)
            src = R / f"input_{ds}.csv" if impl == "input" else R / ds / impl / "rep1.csv.gz"
            df = pl.read_csv(src)
            if impl == "input":
                df = df.drop("batch")
            df.write_csv(d / "emb_harmony.csv")
            df.select("cell_id", pl.lit(0).alias("cluster")).write_csv(d / "clusters.csv")
            # score.py reads emb_<name>.csv.gz
            with open(d / "emb_harmony.csv", "rb") as f, gzip.open(d / "emb_harmony.csv.gz", "wb") as g:
                shutil.copyfileobj(f, g)
            (d / "emb_harmony.csv").unlink()


def knn(x, k=15):
    return NearestNeighbors(n_neighbors=k + 1).fit(x).kneighbors(x)[1][:, 1:]


def report():
    runs = pl.read_csv(R / "runs.csv")
    base = runs.filter(pl.col("impl").str.starts_with("none")).group_by("size", "impl").agg(
        pl.col("max_rss_bytes").median().alias("base"))
    t = runs.filter(~pl.col("impl").str.starts_with("none")).group_by("size", "impl").agg(
        pl.col("seconds").median().alias("median_s"), pl.col("seconds").min().alias("min_s"),
        pl.col("seconds").max().alias("max_s"), pl.col("max_rss_bytes").median().alias("rss"))
    t = t.with_columns(pl.when(pl.col("impl") == "harmonypy").then(pl.lit("none_py")).otherwise(pl.lit("none_r")).alias("b"))
    t = t.join(base, left_on=["size", "b"], right_on=["size", "impl"]).with_columns(
        ((pl.col("rss") - pl.col("base")) / 2**30).round(2).alias("extra_GB")).drop("rss", "base", "b")

    # kNN agreement with harmonypy on a 50k subsample
    agree = []
    for ds in ["splat_100k", "splat_1m"]:
        ref = pl.read_csv(R / ds / "harmonypy" / "rep1.csv.gz")
        rng = np.random.default_rng(42)
        idx = np.sort(rng.choice(ref.height, min(50_000, ref.height), replace=False))
        nn_ref = knn(ref.drop("cell_id").to_numpy()[idx])
        for impl in IMPLS:
            e = pl.read_csv(R / ds / impl / "rep1.csv.gz")
            assert (e["cell_id"] == ref["cell_id"]).all()
            nn = knn(e.drop("cell_id").to_numpy()[idx])
            ov = np.mean([len(set(a) & set(b)) / 15 for a, b in zip(nn, nn_ref)])
            agree.append({"size": ds, "impl": impl, "knn_overlap_vs_harmonypy": round(float(ov), 3)})
    t = t.join(pl.DataFrame(agree), on=["size", "impl"])

    q = []
    for ds in ["splat_100k", "splat_1m"]:
        qq = pl.read_csv(R / f"score_{ds}" / "quality.csv").select(
            "tool", "harmony_knn_purity", "harmony_knn_purity_rarest", "harmony_batch_mix",
            "harmony_asw_group", "harmony_probe_ari").with_columns(pl.lit(ds).alias("size"))
        q.append(qq)
    t = t.join(pl.concat(q), left_on=["size", "impl"], right_on=["size", "tool"], how="left").sort("size", "median_s")
    with pl.Config(tbl_formatting="MARKDOWN", tbl_hide_column_data_types=True, tbl_hide_dataframe_shape=True,
                   tbl_cols=-1, tbl_rows=-1, tbl_width_chars=2000):
        print(t)
        print(pl.concat(q).filter(pl.col("tool") == "input"))


stage() if sys.argv[1] == "stage" else report()
