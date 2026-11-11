"""bixverse (Python) pipeline, the steps and settings of bixverse.R.
Usage: bixverse_py.py <data_dir> <out_dir> <scratch_dir>

Does not import common.py: that pulls in pandas, which this image lacks."""

import gzip
import os
import sys
import time
from contextlib import contextmanager
from importlib.metadata import version
from pathlib import Path

import numpy as np
import polars as pl

import bixverse as bv
import bixverse.embed
from bixverse.params import MinQualityParams, NeighboursParams, PcaParams

data, out, scratch = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
print(f"bixverse {version('bixverse')}, manifolds-rs {version('manifolds-rs')}", flush=True)

MT_MAX = float(os.environ["MT_MAX"])
MIN_CELLS = int(os.environ["MIN_CELLS"])
TRUTH_COL, BATCH_COL = os.environ["TRUTH_COL"], os.environ["BATCH_COL"]
DGE_COL, DGE_CTRL, DGE_CASE = os.environ["DGE_COL"], os.environ["DGE_CTRL"], os.environ["DGE_CASE"]
GENE_COL = os.environ.get("GENE_COL", "")
# the dataset the /var _index attribute names; the prescan does not follow it.
# The package has no attribute reader and the image no h5py, so run.sh passes it
VAR_INDEX = os.environ.get("VAR_INDEX", "gene_name")
CSC_MEM_GB = float(os.environ.get("BIX_CSC_GB", "8"))

# one plate per file, named by the file name up to the first underscore
h5_paths = {p.stem.split("_")[0]: p for p in sorted(data.glob("*.h5ad"))}

steps = open(out / "steps.csv", "w")
steps.write("step,start,end\n")


@contextmanager
def step(name):
    start = time.time()
    yield
    steps.write(f"{name},{start:.3f},{time.time():.3f}\n")
    steps.flush()
    print(f">>> {name}: {time.time() - start:.1f} s <<<", flush=True)


def obs_col(sc, name):
    """obs names may come back lowercased on load, as in R."""
    return next(c for c in sc.obs_columns() if c.lower() == name.lower())


qc_params = MinQualityParams(min_unique_genes=100, min_lib_size=250, min_cells=MIN_CELLS, target_size=1e4)

# load includes the pre-filter and the log-normalisation in one streaming pass
# over all plates; a single plate (the pilot) goes through load_h5ad
with step("load"):
    store = scratch / "bixverse"
    paths = list(h5_paths.values())
    if len(paths) == 1:
        sc = bv.io.load_h5ad(store, paths[0], qc=qc_params, csc_mem_gb=CSC_MEM_GB)
    else:
        prescan = bv.io.prescan_h5ad_files(
            {k: str(v) for k, v in h5_paths.items()}, gene_universe="intersection", var_index=VAR_INDEX
        )
        sc = bv.io.load_multi_h5ad(store, prescan, qc=qc_params, csc_mem_gb=CSC_MEM_GB)

with step("qc"):
    ids = pl.Series(sc.gene_ids().astype(str))
    # gene symbols are the gene ids unless GENE_COL names a var column
    var = sc.var()
    gene_col = next((c for c in var.columns if GENE_COL and c.lower() == GENE_COL.lower()), None)
    names = var[gene_col].cast(pl.String) if gene_col else ids
    mt = ids.filter(names.str.starts_with("MT-")).to_list()
    bv.qc.gene_set_proportions(sc, {"MT": mt})
    qc_df = sc.obs(cols=["cell_idx", "lib_size", "nnz", "MT"], filtered=True)
    # MT comes back as a proportion or a percentage depending on version
    mt_cut = MT_MAX / 100 if qc_df["MT"].max() <= 1 else MT_MAX
    keep = qc_df.filter(
        (pl.col("MT") <= mt_cut) & (pl.col("lib_size") >= 750) & (pl.col("nnz") >= 250)
    )["cell_idx"].to_numpy()
    sc.set_cells_to_keep(keep)

with step("hvg"):
    bv.pp.find_hvg(sc, hvg_no=2000)

# PCA_SOLVER: "auto" (sparse Lanczos, the default) or "covariance" (sparse Gram)
with step("pca"):
    bv.pp.calculate_pca(sc, 30, pca_params=PcaParams(svd_solver=os.environ.get("PCA_SOLVER", "auto")))

with step("harmony"):
    bv.integrate.harmony(sc, obs_col(sc, BATCH_COL))

with step("knn_snn"):
    bv.graph.find_neighbours(sc, embd_to_use="harmony", neighbours_params=NeighboursParams(knn_method="nndescent"))

with step("umap"):
    # randomised = FALSE is the manifoldsR default bixverse.R runs with
    bv.embed.umap(sc, embd_to_use="harmony", params=bv.embed.umap_defaults().set_params(randomised=False))

with step("dge"):
    kept = sc.cells_to_keep
    obs = sc.obs(indices=kept, cols=["cell_idx", obs_col(sc, DGE_COL)])
    grp = obs[:, 1].cast(pl.String)
    markers = bv.de.find_markers(
        sc,
        obs["cell_idx"].filter(grp == DGE_CASE).to_numpy(),
        obs["cell_idx"].filter(grp == DGE_CTRL).to_numpy(),
        verbose=False,
    )

# a random 200k cells, drawn as in common.py's write_embs
labels = pl.DataFrame({
    "cell_id": sc.cell_ids(kept).astype(str),
    "truth": sc.obs(indices=kept, cols=[obs_col(sc, TRUTH_COL)])[:, 0].cast(pl.String),
    "batch": sc.obs(indices=kept, cols=[obs_col(sc, BATCH_COL)])[:, 0].cast(pl.String),
})
rng = np.random.default_rng(42)
idx = np.sort(rng.choice(labels.height, min(labels.height, 200_000), replace=False))
with gzip.open(out / "score_cells.csv.gz", "wb") as gz:
    labels[idx].write_csv(gz)
for name in ["harmony", "umap"]:
    emb = sc.cache.embeddings[name][idx]
    with gzip.open(out / f"emb_{name}.csv.gz", "wb") as gz:
        pl.DataFrame({str(i): emb[:, i] for i in range(emb.shape[1])}).write_csv(gz)
markers.write_csv(out / "markers.csv")

print(f"cells after QC: {labels.height}, DGE genes: {markers.height}")
