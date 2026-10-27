"""CyteArc pipeline. Usage: cytearc_pipeline.py <data_dir> <out_dir> <scratch_dir>"""

import os
import sys
import time
from contextlib import contextmanager
from pathlib import Path

import numpy as np
import pandas as pd

import cytearc

data, out, scratch = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
cytearc.configure_output(level="WARNING", progress=False)

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
TRUTH = (data / "cells_truth.tsv.gz").exists()
DGE_COL = "Group" if TRUTH else "sample"
store = str(scratch / "cytearc.zarr")

with step("load"):
    # the import writes both cell-major counts and the gene-major countsT
    if INPUT == "h5ad":
        reader = cytearc.H5adReader.from_inspect(cytearc.inspect_h5ad(str(data / "DGE.h5ad")))
        cytearc.H5adToZarr(reader, zarr_loc=store).dump()
    else:
        reader = cytearc.MtxReader(cytearc.inspect_mtx(str(data))[0])
        cytearc.MtxToZarr(reader, zarr_loc=store).dump()
    # -1 keeps the open from dropping cells; the pre-filter below does it
    ds = cytearc.DataStore(store, min_features_per_cell=-1)
    # same pre-filter as bixverse: genes in >= 5 cells (the DGE universe), then
    # cells with >= 100 genes and >= 250 UMIs. Filters return selections,
    # nothing is removed from the store. Bounds are exclusive by default.
    all_cells = ds.snapshot_cell_selection("I")
    genes = ds.features.detected(all_cells, min_cells=5)
    pre = ds.qc.filter(["RNA_nFeatures", "RNA_nCounts"], [100, 250], [None, None],
                       cell_selection=all_cells, keep_bounds=True)

# LOAD_ONLY=1: stop once the on-disk store is written, to measure its size
if os.environ.get("LOAD_ONLY") == "1":
    sys.exit(0)

with step("qc"):
    cells = ds.qc.filter(["RNA_nCounts", "RNA_nFeatures"], [750, 250], [None, None],
                         cell_selection=pre, keep_bounds=True)
    # no MT genes in the simulation, so no RNA_percentMito column there
    if "RNA_percentMito" in ds.cells.columns:
        cells = ds.qc.filter(["RNA_percentMito"], [None], [5], cell_selection=cells)

# normalisation is lazy and runs on the HVGs, so it sits after HVG selection
with step("hvg"):
    hvg = ds.features.hvgs(cells, top_n=2000, show_plot=False)

with step("normalise"):
    normalized = ds.features.normalize(cells, hvg)

with step("pca"):
    pca = ds.reduction.pca(normalized, dims=30)

with step("harmony"):
    harmony = ds.reduction.harmony(pca, ["sample"])

with step("knn_snn"):
    ann = ds.graph.ann_index(harmony)
    neighbors = ds.graph.neighbors(ann, coordinates=harmony, k=15)
    graph = ds.graph.connectivity(neighbors)

with step("cluster"):
    leiden = ds.clusters.leiden(graph, resolution=1.0)

with step("umap"):
    # their recipe seeds UMAP with k-means on the same coordinates as the graph
    umap = ds.embeddings.umap(graph, ds.embeddings.initialization(harmony))

with step("dge"):
    groups = ds.snapshot_cluster_labels(DGE_COL, cell_selection=cells)
    markers = ds.markers.search(groups, features=genes)

ids = ds.cells.fetch_all("ids")[np.asarray(ds.artifacts.load(cells)["values"][:], dtype=bool)]


def values(ref, key="values"):
    return np.asarray(ds.artifacts.load(ref)[key][:])


pd.DataFrame({"leiden": values(leiden)}, index=pd.Index(ids, name="cell_id")).to_csv(out / "clusters.csv")
if TRUTH:
    table = ds.markers.load(marker=markers, min_frac_exp=None, min_auc=None, max_p_adj=None)
    # AUC centred at 0, as for scrapper: signed, higher = more up
    table.assign(score=table["auc"] - 0.5).rename(columns={"group_id": "group", "feature_name": "gene"})[
        ["group", "gene", "score"]
    ].to_csv(out / "markers.csv", index=False)
    names = ds.RNA.feats.fetch_all("names")
    pd.Series(names[values(hvg).astype(bool)], name="gene").to_csv(out / "hvg.csv", index=False)
    for name, ref, key in [("pca", pca, "data"), ("harmony", harmony, "data"), ("umap", umap, "values")]:
        pd.DataFrame(values(ref, key), index=ids).to_csv(out / f"emb_{name}.csv.gz", index_label="cell_id")

print(f"cells after QC: {len(ids)}, clusters: {len(np.unique(values(leiden)))}")
