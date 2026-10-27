"""Scanpy with X as a lazy Dask array. Usage: scanpy_dask.py <data_dir> <out_dir>"""

import os
import sys
from pathlib import Path

import anndata as ad
import dask
import h5py
import harmonypy
import numpy as np
import pandas as pd
import scanpy as sc

sys.path.insert(0, "/bench/pipelines")
from common import (
    BATCH_COL,
    DGE_CASE,
    DGE_COL,
    DGE_CTRL,
    GENE_COL,
    MT_MAX,
    TRUTH_COL,
    h5_paths,
    step_timer,
    write_embs,
)

data, out = Path(sys.argv[1]), Path(sys.argv[2])
THREADS = 8
sc.settings.n_jobs = THREADS
CHUNK = int(os.environ.get("CHUNK", "50000"))
step = step_timer(out)


def read_plate(name, path):
    # X stays on disk as a dask array of CSR row chunks; obs and var are small
    with h5py.File(path) as f:
        a = ad.AnnData(obs=ad.io.read_elem(f["obs"]), var=ad.io.read_elem(f["var"]))
        a.X = ad.experimental.read_elem_lazy(f["X"], chunks=(CHUNK, a.n_vars))
    a.obs_names = name + "_" + a.obs_names
    return a


with step("load"):
    # plates bound lazily on the shared genes
    adata = ad.concat([read_plate(n, p) for n, p in h5_paths(data).items()], join="inner", merge="same")
    # same pre-filter as bixverse: genes first, then cells
    sc.pp.filter_genes(adata, min_cells=5)
    sc.pp.filter_cells(adata, min_genes=100)
    sc.pp.filter_cells(adata, min_counts=250)

with step("qc"):
    names = adata.var[GENE_COL] if GENE_COL else adata.var_names.to_series()
    adata.var["mt"] = names.str.startswith("MT-").values

    # calculate_qc_metrics peaks at 16.6 GB transiently on 500k cells under
    # dask (independent of chunk size); the three per-cell sums QC needs,
    # as per-block reductions, peak at 6.2 GB
    def per_row(a, fn):
        return a.map_blocks(
            lambda b: np.asarray(fn(b)).reshape(-1, 1),
            dtype=np.float64,
            chunks=(a.chunks[0], (1,)),
        )

    total, ngenes, mt = (
        np.asarray(v).ravel()
        for v in dask.compute(
            per_row(adata.X, lambda b: b.sum(axis=1)),
            per_row(adata.X, lambda b: np.diff(b.indptr)),
            per_row(adata.X[:, adata.var["mt"].values], lambda b: b.sum(axis=1)),
        )
    )
    adata.obs["total_counts"] = total
    adata.obs["n_genes_by_counts"] = ngenes
    adata.obs["pct_counts_mt"] = 100 * mt / total
    keep = (
        (adata.obs["pct_counts_mt"] <= MT_MAX)
        & (adata.obs["total_counts"] >= 750)
        & (adata.obs["n_genes_by_counts"] >= 250)
    ).values
    adata = adata[keep].copy()

with step("normalise"):
    sc.pp.normalize_total(adata, target_sum=1e4)
    sc.pp.log1p(adata)

with step("hvg"):
    sc.pp.highly_variable_genes(adata, n_top_genes=2000)

with step("pca"):
    sc.pp.pca(adata, n_comps=30)
    # the projection stays lazy until computed
    adata.obsm["X_pca"] = np.asarray(adata.obsm["X_pca"].compute())

with step("harmony"):
    # sc.external.pp.harmony_integrate transposes the output, which breaks on
    # harmonypy 2.x (Z_corr is already cells x PCs)
    z = harmonypy.run_harmony(adata.obsm["X_pca"], adata.obs, BATCH_COL, ncores=THREADS).Z_corr
    adata.obsm["X_pca_harmony"] = np.asarray(z if z.shape[0] == adata.n_obs else z.T)

with step("knn_snn"):
    sc.pp.neighbors(adata, n_neighbors=15, use_rep="X_pca_harmony")

with step("umap"):
    sc.tl.umap(adata)

# Wilcoxon fails on dask arrays in scanpy 1.12.4 (numba TypingError in
# _select_top_n), so the two groups are pulled into memory first; that
# materialisation is part of the step
with step("dge"):
    sub = adata[adata.obs[DGE_COL].isin([DGE_CASE, DGE_CTRL]).values].copy()
    sub.X = sub.X.compute()
    sub.obs[DGE_COL] = sub.obs[DGE_COL].astype(str).astype("category")
    sc.tl.rank_genes_groups(
        sub, DGE_COL, groups=[DGE_CASE], reference=DGE_CTRL, method="wilcoxon", n_genes=sub.n_vars
    )

labels = pd.DataFrame(
    {
        "cell_id": adata.obs_names,
        "truth": adata.obs[TRUTH_COL].values,
        "batch": adata.obs[BATCH_COL].values,
    }
)
write_embs(out, {"harmony": adata.obsm["X_pca_harmony"], "umap": adata.obsm["X_umap"]}, labels)
sc.get.rank_genes_groups_df(sub, group=DGE_CASE).to_csv(out / "markers.csv", index=False)

print(f"cells after QC: {adata.n_obs}, DGE cells: {sub.n_obs}")
