"""CyteArc pipeline. Usage: cytearc.py <data_dir> <out_dir> <scratch_dir>"""

import shutil
import sys
from pathlib import Path

import numpy as np
import pandas as pd

import cytearc

sys.path.insert(0, "/bench/pipelines")
from common import BATCH_COL, DGE_CASE, DGE_COL, DGE_CTRL, MT_MAX, TRUTH_COL, h5_paths, step_timer, write_embs


def merged_cols(single):
    """DataStoreMerge prefixes the source metadata columns with its prepend_text."""
    pre = "" if single else "orig_"
    return (f"{pre}{c}" for c in (TRUTH_COL, BATCH_COL, DGE_COL))


def main():
    data, out, scratch = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    cytearc.configure_output(level="WARNING", progress=False)
    step = step_timer(out)
    store = str(scratch / "cytearc.zarr")

    with step("load"):
        # one import per plate (cell-major counts plus the gene-major countsT),
        # merged into one store; the per-plate stores are dropped afterwards
        # (a single plate, the pilot, imports straight into the store: the merge
        # needs two sources)
        plates = h5_paths(data)
        single = len(plates) == 1
        for name, path in plates.items():
            reader = cytearc.H5adReader.from_inspect(cytearc.inspect_h5ad(str(path)))
            cytearc.H5adToZarr(reader, zarr_loc=store if single else str(scratch / f"{name}.zarr")).dump()
        if not single:
            cytearc.DataStoreMerge(
                [cytearc.DataStore(str(scratch / f"{n}.zarr"), min_features_per_cell=-1) for n in plates],
                zarr_path=store,
                names=list(plates),
            ).dump()
            for name in plates:
                shutil.rmtree(scratch / f"{name}.zarr")
        TRUTH, BATCH, DGE = merged_cols(single)
        # -1 keeps the open from dropping cells; the pre-filter below does it
        ds = cytearc.DataStore(store, min_features_per_cell=-1)
        # same pre-filter as bixverse: genes in >= 5 cells (the DGE universe), then
        # cells with >= 100 genes and >= 250 UMIs. Filters return selections,
        # nothing is removed from the store. Bounds are exclusive by default.
        all_cells = ds.snapshot_cell_selection("I")
        genes = ds.features.detected(all_cells, min_cells=5)
        pre = ds.qc.filter(["RNA_nFeatures", "RNA_nCounts"], [100, 250], [None, None],
                           cell_selection=all_cells, keep_bounds=True)

    with step("qc"):
        cells = ds.qc.filter(["RNA_nCounts", "RNA_nFeatures"], [750, 250], [None, None],
                             cell_selection=pre, keep_bounds=True)
        cells = ds.qc.filter(["RNA_percentMito"], [None], [MT_MAX], cell_selection=cells, keep_bounds=True)

    # normalisation is lazy and runs on the HVGs, so it sits after HVG selection
    with step("hvg"):
        hvg = ds.features.hvgs(cells, top_n=2000, show_plot=False)

    with step("normalise"):
        normalized = ds.features.normalize(cells, hvg)

    with step("pca"):
        pca = ds.reduction.pca(normalized, dims=30)

    with step("harmony"):
        harmony = ds.reduction.harmony(pca, [BATCH])

    with step("knn_snn"):
        ann = ds.graph.ann_index(harmony)
        neighbors = ds.graph.neighbors(ann, coordinates=harmony, k=15)
        graph = ds.graph.connectivity(neighbors)

    with step("umap"):
        # their recipe seeds UMAP with k-means on the same coordinates as the graph
        umap = ds.embeddings.umap(graph, ds.embeddings.initialization(harmony))

    # one-vs-rest over the two groups of the subset is the two-group test
    with step("dge"):
        labels = ds.snapshot_cluster_labels(DGE, cell_selection=cells)
        sub = ds.select_cells(labels, include=[DGE_CASE, DGE_CTRL])
        groups = ds.snapshot_cluster_labels(labels, cell_selection=sub)
        markers = ds.markers.search(groups, features=genes)

    def values(ref, key="values"):
        return np.asarray(ds.artifacts.load(ref)[key][:])

    mask = values(cells).astype(bool)
    labels = pd.DataFrame(
        {
            "cell_id": ds.cells.fetch_all("ids")[mask],
            "truth": ds.cells.fetch_all(TRUTH)[mask],
            "batch": ds.cells.fetch_all(BATCH)[mask],
        }
    )
    write_embs(out, {"harmony": values(harmony, "data"), "umap": values(umap)}, labels)
    table = ds.markers.load(marker=markers, min_frac_exp=None, min_auc=None, max_p_adj=None)
    table[table["group_id"].astype(str) == DGE_CASE].to_csv(out / "markers.csv", index=False)

    print(f"cells after QC: {len(labels)}, DGE genes: {int((table['group_id'].astype(str) == DGE_CASE).sum())}")


# CyteArc's H5AD writer starts spawn workers, which re-import this script
if __name__ == "__main__":
    main()
