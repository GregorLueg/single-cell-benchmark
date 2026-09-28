"""Scanpy pipeline. Usage: scanpy_pipeline.py <data_dir> <out_dir>"""

import os
import sys
import time
from contextlib import contextmanager
from pathlib import Path

import anndata as ad
import h5py
import harmonypy
import numpy as np
import pandas as pd
import scanpy as sc
from openTSNE import TSNE

data, out = Path(sys.argv[1]), Path(sys.argv[2])
THREADS = 8
sc.settings.n_jobs = THREADS

steps = open(out / "steps.csv", "w")
steps.write("step,start,end\n")


@contextmanager
def step(name):
    start = time.time()
    yield
    steps.write(f"{name},{start},{time.time()}\n")
    steps.flush()
    print(f">>> {name}: {time.time() - start:.1f} s <<<", flush=True)


INPUT = os.environ.get("INPUT", "mtx")

with step("load"):
    if INPUT == "h5ad":
        adata = sc.read_h5ad(data / "DGE.h5ad")
    elif INPUT == "dask":
        # X stays on disk as a dask array of CSR row chunks; obs and var are small
        chunk = int(os.environ.get("CHUNK", "50000"))
        with h5py.File(data / "DGE.h5ad") as f:
            adata = ad.AnnData(obs=ad.io.read_elem(f["obs"]), var=ad.io.read_elem(f["var"]))
            adata.X = ad.experimental.read_elem_lazy(f["X"], chunks=(chunk, adata.n_vars))
    else:
        adata = sc.read_mtx(data / "DGE.mtx")
        adata.obs = pd.read_csv(data / "cell_metadata.csv", index_col=0)
        adata.var = pd.read_csv(data / "all_genes.csv", index_col=0)
    # same pre-filter as bixverse: genes first, then cells
    sc.pp.filter_genes(adata, min_cells=5)
    sc.pp.filter_cells(adata, min_genes=100)
    sc.pp.filter_cells(adata, min_counts=250)

with step("qc"):
    adata.var["mt"] = adata.var["gene_name"].str.startswith("MT-")
    sc.pp.calculate_qc_metrics(adata, qc_vars=["mt"], percent_top=None, log1p=False, inplace=True)
    keep = (
        (adata.obs["pct_counts_mt"] < 5)
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
    if INPUT == "dask":
        # the projection stays lazy until computed
        adata.obsm["X_pca"] = np.asarray(adata.obsm["X_pca"].compute())

with step("harmony"):
    # sc.external.pp.harmony_integrate transposes the output, which breaks on
    # harmonypy 2.x (Z_corr is already cells x PCs)
    z = harmonypy.run_harmony(adata.obsm["X_pca"], adata.obs, "sample").Z_corr
    adata.obsm["X_pca_harmony"] = np.asarray(z if z.shape[0] == adata.n_obs else z.T)

with step("knn_snn"):
    sc.pp.neighbors(adata, n_neighbors=15, use_rep="X_pca_harmony")

with step("cluster"):
    sc.tl.leiden(adata, resolution=1.0, flavor="igraph", n_iterations=2)

with step("umap"):
    sc.tl.umap(adata)

with step("tsne_default"):
    sc.tl.tsne(adata, use_rep="X_pca_harmony", perplexity=30, n_jobs=THREADS)

with step("tsne_fft"):
    emb = TSNE(perplexity=30, negative_gradient_method="fft", n_jobs=THREADS, random_state=42).fit(
        adata.obsm["X_pca_harmony"]
    )
    adata.obsm["X_tsne_fft"] = np.asarray(emb)

adata.obs[["leiden"]].to_csv(out / "clusters.csv")
print(f"cells after QC: {adata.n_obs}, clusters: {adata.obs['leiden'].nunique()}")
