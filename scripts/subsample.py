# /// script
# requires-python = ">=3.12"
# dependencies = ["polars>=1.30"]
# ///
"""Subsample the Parse 1M PBMC mtx (cells as rows) to n random cells."""

import sys
from pathlib import Path

import polars as pl

src, dst, n = Path(sys.argv[1]).expanduser(), Path(sys.argv[2]).expanduser(), int(sys.argv[3])
dst.mkdir(parents=True, exist_ok=True)

obs = pl.read_csv(src / "cell_metadata_1M_PBMC.csv")
keep = (
    obs.with_row_index("old", offset=1)
    .sample(n=n, seed=42)
    .sort("old")
    .with_row_index("new", offset=1)
)
mapping = keep.select(pl.col("old").cast(pl.Int64), pl.col("new").cast(pl.Int64))

# 2 comment lines + 1 dims line
triplets = (
    pl.scan_csv(
        src / "DGE_1M_PBMC.mtx",
        separator=" ",
        has_header=False,
        skip_rows=3,
        new_columns=["old", "gene", "value"],
        schema_overrides={"old": pl.Int64, "gene": pl.Int64, "value": pl.Int64},
    )
    .join(mapping.lazy(), on="old", how="inner")
    .select("new", "gene", "value")
    .sort(["new", "gene"])
    .collect(engine="streaming")
)

n_genes = pl.read_csv(src / "all_genes_1M_PBMC.csv").height
with open(dst / "DGE.mtx", "w") as f:
    f.write("%%MatrixMarket matrix coordinate integer general\n")
    f.write(f"{n} {n_genes} {triplets.height}\n")
    triplets.write_csv(f, separator=" ", include_header=False)

keep.drop("old", "new").write_csv(dst / "cell_metadata.csv")
(dst / "all_genes.csv").write_bytes((src / "all_genes_1M_PBMC.csv").read_bytes())
print(f"{n} cells, {n_genes} genes, {triplets.height} nnz")
