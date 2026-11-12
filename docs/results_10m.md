# Results: 10M cells

Work in progress, no results yet. The step up from [1M](results_1m.md): the
Parse Biosciences 10M PBMC data set, 12 donors treated with 90 cytokines plus
a PBS control, in one experiment and one h5ad. It replaces the Tahoe-100M
two-plate run planned earlier: a real donor batch effect for Harmony to
remove, cell type labels to score against, and one file, so every framework
loads the same way.

## Data

`20260203_Parse_10M_PBMC_cytokines.h5ad` from
[Parse](https://www.parsebiosciences.com/datasets/10-million-human-pbmcs-in-a-single-experiment/),
CC BY-NC 4.0.

- 9,697,974 cells x 40,352 genes, already filtered by Parse.
- Raw counts, CSR. 18.8 billion nonzeros (about 1,940 genes per cell).
- `X/data` float32, `X/indices` and `X/indptr` int64, gzip level 4 without
  shuffle: the layout `write_h5ad(compression="gzip")` gives, so it is used as
  shipped. 44.4 GB on disk; held in memory, about 226 GB.
- Gene symbols as var names, no duplicates, 29 `MT-` genes.
- obs: `donor` (12), `cytokine` (91 values, PBS included), `treatment` (PBS or
  cytokine), `cell_type` (18), `sample`, plus Parse's own QC columns.

At that size nothing that holds the counts in memory fits a 48 GB cap; only
the out-of-core designs run, plus one brisc attempt to show where in-memory
ends. Parse's own Scanpy tutorial on this file took about 13 h on a large
machine (Harmony 5 h 18 min, UMAP 2 h 25 min).

## Plan

- Docker, 8 cores, 48 GB cap, 5 h wall per run, one framework per window,
  cold file cache.
- Steps: load, QC (MT computed by each framework, cut to be set from the
  distribution), HVG, PCA, Harmony on `donor`, kNN/sNN, Leiden, DGE on a fixed
  list of cytokines against PBS, UMAP last, so a timeout only loses UMAP.
- Scores: cluster ARI against `cell_type`, donor mixing after Harmony.
- Frameworks: bixverse (R and Python), Scanpy dask (t-test DGE), CyteArc,
  Seurat + BPCells, brisc. Then bixverse natively on the CPU against wgpu and
  MLX.
