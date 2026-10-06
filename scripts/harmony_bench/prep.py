# /// script
# requires-python = ">=3.12"
# dependencies = ["polars>=1.30"]
# ///
"""Same Harmony input for every implementation: bixverse 0.6.0's PCA (h5ad run)
plus the true batch labels. Usage: prep.py <out_dir>"""

import sys
from pathlib import Path

import polars as pl

W = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1])
for ds in ["splat_100k", "splat_1m"]:
    pca = pl.read_csv(W / f"results/{ds}/bixverse_h5ad/emb_pca.csv.gz")
    truth = pl.read_csv(W / f"data/{ds}/cells_truth.tsv.gz", separator="\t").select(
        pl.col("Cell").alias("cell_id"), pl.col("Batch").alias("batch")
    )
    df = truth.join(pca, on="cell_id", how="inner", maintain_order="right")
    assert df.height == pca.height
    df.write_csv(out / f"input_{ds}.csv")
    print(ds, df.shape)
