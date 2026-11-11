"""bixverse (Python) pipeline, the steps and settings of bixverse.R.
Usage: bixverse_pipeline.py <data_dir> <out_dir> <scratch_dir>"""

import gzip
import os
import sys
import time
from contextlib import contextmanager
from importlib.metadata import version
from pathlib import Path

import manifolds_rs as mf
import numpy as np
import polars as pl

import bixverse as bv
import bixverse.embed
from bixverse.params import FastClusterParams, MinQualityParams, MtxIoParams, NeighboursParams

data, out, scratch = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
print(f"bixverse {version('bixverse')}, manifolds-rs {version('manifolds-rs')}", flush=True)

steps = open(out / "steps.csv", "w")
steps.write("step,start,end\n")


@contextmanager
def step(name):
    start = time.time()
    yield
    steps.write(f"{name},{start:.3f},{time.time():.3f}\n")
    steps.flush()
    print(f">>> {name}: {time.time() - start:.1f} s <<<", flush=True)


TRUTH = (data / "cells_truth.tsv.gz").exists()
DGE_COL = "Group" if TRUTH else "sample"
KNN_METHOD = os.environ.get("BIX_KNN", "nndescent")
TSNE_KNN_METHOD = os.environ.get("BIX_TSNE_KNN", "kmknn")
CSC_MEM_GB = float(os.environ.get("BIX_CSC_GB", "8"))
genes = pl.read_csv(data / "all_genes.csv")
mt_ids = genes.filter(pl.col("gene_name").str.starts_with("MT-"))["gene_id"].to_list()

qc_params = MinQualityParams(min_unique_genes=100, min_lib_size=250, min_cells=5, target_size=1e4)

# load includes the pre-filter and the log-normalisation, as in bixverse.R
with step("load"):
    store = scratch / "bixverse"
    if os.environ.get("INPUT", "mtx") == "h5ad":
        sc = bv.io.load_h5ad(store, data / "DGE.h5ad", qc=qc_params, csc_mem_gb=CSC_MEM_GB)
    else:
        mtx_params = MtxIoParams(
            path_mtx=str(data / "DGE.mtx.gz"),
            path_obs=str(data / "cell_metadata.csv"),
            path_var=str(data / "all_genes.csv"),
            cells_as_rows=True,
            has_hdr=True,
        )
        sc = bv.io.load_mtx(store, mtx_params, qc=qc_params, csc_mem_gb=CSC_MEM_GB)

if os.environ.get("LOAD_ONLY") == "1":
    sys.exit(0)

with step("qc"):
    var_ids = set(sc.gene_ids().tolist())
    mt = [g for g in mt_ids if g in var_ids]
    cols = ["cell_idx", "lib_size", "nnz"]
    # simulated data has no MT genes, and an empty gene set is an error
    if mt:
        bv.qc.gene_set_proportions(sc, {"MT": mt})
        qc_df = sc.obs(cols=[*cols, "MT"], filtered=True)
    else:
        qc_df = sc.obs(cols=cols, filtered=True).with_columns(MT=pl.lit(0.0))
    keep = qc_df.filter(
        (pl.col("MT") < 0.05) & (pl.col("lib_size") >= 750) & (pl.col("nnz") >= 250)
    )["cell_idx"].to_numpy()
    sc.set_cells_to_keep(keep)

with step("hvg"):
    bv.pp.find_hvg(sc, hvg_no=2000)

with step("pca"):
    bv.pp.calculate_pca(sc, 30)

with step("harmony"):
    bv.integrate.harmony(sc, "sample")

with step("knn_snn"):
    bv.graph.find_neighbours(
        sc, embd_to_use="harmony", neighbours_params=NeighboursParams(knn_method=KNN_METHOD)
    )

with step("cluster"):
    bv.graph.find_clusters(sc, res=1.0, name="leiden")

with step("cluster_fast"):
    n = sc.cache.embeddings["harmony"].shape[0]
    fc = bv.graph.fast_cluster(
        sc,
        embd_to_use="harmony",
        resolutions=(1.0, 2.0),
        fc_params=FastClusterParams(n_centroids=int(4 * np.sqrt(n)), algorithm="leiden"),
        verbose=False,
    )
    # one res_<value> column per resolution, in resolution order
    res_cols = [c for c in fc.memberships.columns if c != "cell_idx"]
    sc.add_obs(fc.memberships.rename(dict(zip(res_cols, ["leiden_fast", "leiden_fast_r2"]))))

with step("umap"):
    # randomised = FALSE is the manifoldsR default bixverse.R runs with
    bv.embed.umap(
        sc, embd_to_use="harmony", params=bv.embed.umap_defaults().set_params(randomised=False)
    )

# obs names may come back lowercased on load, as in R
dge_col = next(c for c in sc.obs_columns() if c.lower() == DGE_COL.lower())
with step("dge"):
    markers = bv.de.find_all_markers(sc, dge_col, verbose=False)

# all score.py inputs before the tSNE steps, so a tSNE timeout only loses its rows
kept = sc.cells_to_keep
ids = pl.Series("cell_id", sc.cell_ids(kept).astype(str))
obs = sc.obs(indices=kept, cols=["cell_idx", "leiden", "leiden_fast", "leiden_fast_r2"])
for col, f in [("leiden", "clusters"), ("leiden_fast", "clusters_fast"), ("leiden_fast_r2", "clusters_fast_r2")]:
    pl.DataFrame([ids, obs[col]]).write_csv(out / f"{f}.csv")


def write_emb(name, emb):
    cols = [pl.Series(f"{name}_{i + 1}", emb[:, i]) for i in range(emb.shape[1])]
    with gzip.open(out / f"emb_{name}.csv.gz", "wb") as gz:
        pl.DataFrame([ids, *cols]).write_csv(gz)


if TRUTH:
    pl.DataFrame({"gene": sc.gene_ids(sc.map.hvg).astype(str)}).write_csv(out / "hvg.csv")
    write_emb("pca", sc.cache.pca_factors)
    for name in ["harmony", "umap"]:
        write_emb(name, sc.cache.embeddings[name])
    markers.select(
        pl.col("grp").cast(pl.String).alias("group"),
        pl.col("gene_id").cast(pl.String).alias("gene"),
        pl.col("z_scores").alias("score"),
    ).write_csv(out / "markers.csv")


def tsne_params(approx, **optim):
    p = bv.embed.tsne_defaults().set_params(perplexity=30.0, approx=approx, ann=TSNE_KNN_METHOD)
    if optim:
        o = p.get_params()["optim_params"]
        p = p.set_params(
            n_epochs=optim.pop("n_epochs"),
            optim_params=mf.TsneOptim(
                early_exag_iter=o.early_exag_iter,
                early_exag_factor=o.early_exag_factor,
                n_interp_points=o.n_interp_points,
                **optim,
            ),
        )
    return p


with step("tsne_default"):
    bv.embed.tsne(sc, embd_to_use="harmony", params=tsne_params("bh"))
if TRUTH:
    write_emb("tsne", sc.cache.embeddings["tsne"])

with step("tsne_fft"):
    bv.embed.tsne(sc, embd_to_use="harmony", slot_name="tsne_fft", params=tsne_params("fft_3k"))

# tsne_quick: qdtsne's depth-capped Barnes-Hut at the scrapper row's settings
with step("tsne_quick"):
    bv.embed.tsne(
        sc,
        embd_to_use="harmony",
        slot_name="tsne_quick",
        params=tsne_params("bh_qd", n_epochs=500, theta=1.0, max_depth=7),
    )
if TRUTH:
    write_emb("tsne_quick", sc.cache.embeddings["tsne_quick"])

print(
    f"cells after QC: {len(ids)}, clusters: {obs['leiden'].n_unique()}, "
    f"fast clusters: {obs['leiden_fast'].n_unique()} (res 1), {obs['leiden_fast_r2'].n_unique()} (res 2)"
)
