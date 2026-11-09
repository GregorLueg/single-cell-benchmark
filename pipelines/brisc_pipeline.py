"""brisc pipeline, h5ad input only. Usage: brisc_pipeline.py <data_dir> <out_dir>"""

import gzip
import os
import sys
import time
from contextlib import contextmanager
from pathlib import Path

import numpy as np
import polars as pl

import brisc
from brisc import SingleCell, brisc_blas

data, out = Path(sys.argv[1]), Path(sys.argv[2])
THREADS = 8
print(f"brisc {brisc.__version__}, BLAS: {brisc_blas()}", flush=True)

steps = open(out / "steps.csv", "w")
steps.write("step,start,end\n")


@contextmanager
def step(name):
    start = time.time()
    yield
    steps.write(f"{name},{start},{time.time()}\n")
    steps.flush()
    print(f">>> {name}: {time.time() - start:.1f} s <<<", flush=True)


TRUTH = (data / "cells_truth.tsv.gz").exists()
DGE_COL = "Group" if TRUTH else "sample"

with step("load"):
    # num_threads defaults to os.cpu_count(), the VM's core count, not the cap
    sc = SingleCell(str(data / "DGE.h5ad"), num_threads=THREADS)
    # the DGE universe of the other pipelines: genes in >= 5 cells. brisc keeps
    # the matrix whole and tabulates what passes, so nothing is subset here
    kept_genes = sc.var[:, 0].filter(pl.Series(np.bincount(sc.X.indices, minlength=sc.X.shape[1]) >= 5))

# LOAD_ONLY=1: stop after the load, to compare h5ad readers
if os.environ.get("LOAD_ONLY") == "1":
    sys.exit(0)

with step("qc"):
    # both cell cuts cover the harness pre-filter (>= 100 genes, >= 250 UMIs).
    # qc raises on data without MT genes, and the harness has no MALAT1 filter
    has_mt = sc.var[:, 0].cast(pl.String).str.to_uppercase().str.starts_with("MT-").any()
    sc = sc.qc(
        min_genes=250,
        min_counts=750,
        max_mito_fraction=0.05 if has_mt else None,
        nonzero_MALAT1=False,
        allow_float=True,
    )

# hvg works on the raw counts, so it sits before normalisation
with step("hvg"):
    sc = sc.hvg(num_genes=2000, min_cells=5)

with step("normalise"):
    sc = sc.normalize()

with step("pca"):
    sc = sc.pca(num_PCs=30)

with step("harmony"):
    sc = sc.harmonize(batch_column="sample")

with step("knn_snn"):
    sc = sc.neighbors(PC_key="harmony", num_neighbors=15).shared_neighbors()

with step("cluster"):
    sc = sc.cluster(resolution=1)

with step("umap"):
    sc = sc.umap(PC_key="harmony")

with step("dge"):
    markers = sc.find_markers(DGE_COL, all_genes=True)

passed = sc.obs["passed_QC"].to_numpy()
ids = sc.obs[:, 0].filter(sc.obs["passed_QC"]).cast(pl.String).alias("cell_id")
clusters = sc.obs["cluster"].filter(sc.obs["passed_QC"]).alias("leiden")
pl.DataFrame([ids, clusters]).write_csv(out / "clusters.csv")

if TRUTH:
    # fold change in detection rate is inf for genes detected only in the group,
    # which roc_auc_score rejects; keep them on top with a finite value
    top = markers.filter(pl.col("fold_change").is_finite())["fold_change"].max()
    markers.filter(pl.col("gene").is_in(kept_genes.to_list())).select(
        pl.col("cell_type").cast(pl.String).alias("group"),
        pl.col("gene").cast(pl.String),
        pl.when(pl.col("fold_change").is_infinite())
        .then(top + 1)
        .otherwise(pl.col("fold_change"))
        .alias("score"),
        "detection_rate",
        "marker",
    ).write_csv(out / "markers.csv")
    sc.var.filter("highly_variable")[:, 0].cast(pl.String).alias("gene").to_frame().write_csv(out / "hvg.csv")
    for name, key in [("pca", "pca"), ("harmony", "harmony"), ("umap", "umap")]:
        emb = np.asarray(sc.obsm[key])[passed]
        cols = [pl.Series(f"V{i + 1}", emb[:, i]) for i in range(emb.shape[1])]
        with gzip.open(out / f"emb_{name}.csv.gz", "wb") as gz:
            pl.DataFrame([ids, *cols]).write_csv(gz)

print(f"cells after QC: {len(ids)}, clusters: {clusters.n_unique()}")
