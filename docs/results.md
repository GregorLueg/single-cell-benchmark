# Results

Seconds per step, one repeat each. **OOM** marks the step where the container
was killed; **OOM (worker)** where a forked BiocParallel worker was. Peak GB is
cgroup anon memory; the bixverse GPU row is native macOS RSS and not comparable.
Setup and caveats: [methods](methods.md).

Regenerate with `uv run scripts/tables.py results`.

![Wall time per step for every framework and size](figures/steps_heatmap.png)

## 100k cells (69,412 after QC)

| step | bixverse mtx | bixverse h5ad | bixverse GPU (native) | Scanpy mtx | Scanpy h5ad | Scanpy dask | scrapper mtx | scrapper h5ad | Seurat std mtx | Seurat std h5ad | Seurat BPCells | OSCA HDF5 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| load | 10.9 | 6.8 | 6.8 | 21.4 | 3.3 | 5.9 | 42.5 | 6.3 | 43.6 | 9.9 | 15.1 | 38.2 |
| qc | 0.9 | 1.1 | 0.7 | 0.8 | 0.8 | 1.0 | 0.5 | 0.4 | 2.8 | 2.6 | 1.2 | 10.0 |
| normalise | n/a | n/a | n/a | 2.0 | 2.1 | 0.0 | 0.1 | 0.1 | 4.9 | 4.7 | 2.2 | 8.0 |
| hvg | 0.5 | 0.5 | 0.4 | 1.3 | 1.4 | 1.7 | 0.2 | 0.2 | 7.3 | 6.8 | 2.7 | 609.2 |
| pca | 1.5 | 1.5 | 0.5 | 1.4 | 1.5 | 3.9 | 1.8 | 1.6 | 24.5 | 24.0 | 75.3 | 63.4 |
| harmony | 4.7 | 5.0 | 2.1 | 8.7 | 8.5 | 8.5 | 11.1 | 12.1 | 13.4 | 13.0 | 14.2 | 13.9 |
| knn_snn | 1.7 | 1.7 | 1.0 | 28.3 | 29.6 | 23.6 | 4.6 | 4.3 | 13.5 | 13.0 | 13.8 | 28.5 |
| cluster | 1.3 | 1.4 | 1.0 | 1.9 | 2.1 | 2.0 | 8.6 | 8.1 | 17.2 | 16.3 | 18.1 | 7.8 |
| umap | 2.6 | 2.6 | 0.6 | 27.3 | 26.7 | 26.9 | 32.8 | 32.3 | 58.1 | 54.2 | 57.5 | 27.8 |
| tsne_default | 25.9 | 25.7 | 26.3 | 102.9 | 103.1 | 99.5 | 18.2 | 16.5 | 74.4 | 70.9 | 77.9 | 98.9 |
| tsne_matched | n/a | n/a | n/a | n/a | n/a | n/a | 41.5 | 36.9 | n/a | n/a | n/a | n/a |
| tsne_fft | 10.0 | 10.2 | 9.6 | 32.3 | 31.7 | 30.7 | n/a | n/a | 25.8 | 24.0 | 25.7 | n/a |
| **total** | **60** | **57** | **49** | **228** | **211** | **204** | **162** | **119** | **286** | **239** | **304** | **906** |
| total without tSNE | 24 | 21 | 13 | 93 | 76 | 74 | 102 | 65 | 185 | 144 | 200 | 807 |
| **peak GB** | **1.6** | **1.6** | **4.3** | **6.8** | **2.6** | **1.9** | **5.3** | **4.8** | **8.7** | **8.7** | **1.7** | **22.7** |
| peak swap GB | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 3.7 |

## 500k cells (346,259 after QC)

| step | bixverse mtx | bixverse h5ad | bixverse GPU (native) | Scanpy mtx | Scanpy h5ad | Scanpy dask | scrapper mtx | scrapper h5ad | Seurat std mtx | Seurat std h5ad | Seurat BPCells | OSCA HDF5 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| load | 71.7 | 29.0 | 37.6 | **OOM** | 19.0 | 23.3 | **OOM** | 150.3 | **OOM** | **OOM** | 74.7 | 159.5 |
| qc | 2.7 | 3.6 | 2.3 | - | 3.8 | 4.2 | - | 2.1 | - | - | 4.8 | 47.2 |
| normalise | n/a | n/a | n/a | - | 3.5 | 0.0 | - | 0.4 | - | - | 8.3 | 29.3 |
| hvg | 1.0 | 1.0 | 1.0 | - | 3.1 | 5.0 | - | 0.9 | - | - | 9.3 | **OOM (worker)** |
| pca | 3.6 | 3.5 | 2.1 | - | 5.7 | 10.3 | - | 10.2 | - | - | 357.4 | - |
| harmony | 30.9 | 33.1 | 6.8 | - | 58.3 | 58.4 | - | 95.6 | - | - | 91.8 | - |
| knn_snn | 8.9 | 9.5 | 4.0 | - | 32.3 | 27.7 | - | 26.2 | - | - | 89.6 | - |
| cluster | 7.6 | 7.5 | 5.7 | - | 13.4 | 12.9 | - | 83.2 | - | - | 111.2 | - |
| umap | 22.7 | 23.5 | 2.7 | - | 158.0 | 152.4 | - | 149.8 | - | - | 344.4 | - |
| tsne_default | 195.7 | 191.0 | 138.0 | - | 840.4 | 813.0 | - | 98.3 | - | - | 628.7 | - |
| tsne_matched | n/a | n/a | n/a | n/a | n/a | n/a | - | 202.2 | n/a | n/a | n/a | n/a |
| tsne_fft | 86.6 | 86.5 | 34.7 | - | 114.9 | 110.1 | n/a | n/a | - | - | 109.5 | n/a |
| **total** | **431** | **388** | **235** | failed | **1252** | **1217** | failed | **819** | failed | failed | **1830** | failed |
| total without tSNE | 149 | 111 | 62 | failed | 297 | 294 | failed | 519 | failed | failed | 1092 | failed |
| **peak GB** | **6.3** | **6.5** | **10.0** | **22.3** | **14.2** | **6.8** | **22.7** | **22.7** | **22.7** | **22.8** | **5.3** | **22.7** |
| peak swap GB | 0.0 | 0.0 | 0.0 | 3.9 | 0.0 | 0.0 | 3.8 | 3.2 | 3.7 | 3.5 | 0.0 | 3.7 |

## Full data set (684,932 after QC)

| step | bixverse mtx | bixverse h5ad | bixverse GPU (native) | Scanpy mtx | Scanpy h5ad | Scanpy dask | scrapper mtx | scrapper h5ad | Seurat std mtx | Seurat std h5ad | Seurat BPCells | OSCA HDF5 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| load | 111.7 | 71.0 | 70.9 | **OOM** | **OOM** | 42.3 | **OOM** | **OOM** | **OOM** | **OOM** | 139.7 | 315.6 |
| qc | 4.5 | 4.7 | 3.0 | - | - | 7.4 | - | - | - | - | 9.2 | 101.4 |
| normalise | n/a | n/a | n/a | - | - | 0.0 | - | - | - | - | 15.9 | 61.0 |
| hvg | 1.8 | 1.8 | 1.8 | - | - | 9.0 | - | - | - | - | 15.8 | **OOM (worker)** |
| pca | 6.9 | 6.3 | 6.2 | - | - | 17.2 | - | - | - | - | 703.0 | - |
| harmony | 68.7 | 63.9 | 16.6 | - | - | 137.8 | - | - | - | - | 220.1 | - |
| knn_snn | 18.6 | 18.1 | 8.3 | - | - | 33.1 | - | - | - | - | 201.3 | - |
| cluster | 16.7 | 16.4 | 11.8 | - | - | 29.9 | - | - | - | - | 248.7 | - |
| umap | 51.1 | 51.2 | 6.0 | - | - | 352.1 | - | - | - | - | 749.4 | - |
| tsne_default | 506.6 | 504.7 | 323.6 | - | - | 1955.3 | - | - | - | - | 1600.3 | - |
| tsne_fft | 271.8 | 268.6 | 90.1 | - | - | 258.4 | n/a | n/a | - | - | 227.4 | n/a |
| **total** | **1058** | **1007** | **538** | failed | failed | **2843** | failed | failed | failed | failed | **4131** | failed |
| total without tSNE | 280 | 233 | 124 | failed | failed | 629 | failed | failed | failed | failed | 2303 | failed |
| **peak GB** | **10.6** | **9.0** | **16.1** | **22.5** | **22.5** | **9.5** | **22.8** | **22.8** | **22.8** | **22.8** | **9.4** | **22.8** |
| peak swap GB | 0.0 | 0.1 | 0.0 | 3.7 | 3.2 | 0.0 | 3.5 | 3.0 | 3.4 | 3.0 | 0.0 | 3.6 |

## What it shows

![Speed-up per step against in-memory Scanpy at 500k](figures/speedup_vs_scanpy_500k.png)

- **Three frameworks finish the full data set, all out-of-core.** Without
  tSNE: bixverse 3.9 min from h5ad (4.7 min from mtx, 2.1 min on the GPU),
  Scanpy Dask 10.5 min, Seurat + BPCells 38 min. Everything that holds the
  counts in memory dies at load, and OSCA's HDF5 path dies in HVG.
- **Memory is now a tie among the survivors.** Full data peaks: bixverse 9.0
  GB (h5ad) and 10.6 GB (mtx), Scanpy Dask 9.5 GB, Seurat + BPCells 9.4 GB.
- **Each out-of-core design pays somewhere else.** bixverse pays up front to
  convert into its two views (71 s from h5ad on the full data) and is fast
  after. Dask loads in 42 s but re-reads the file on every forced pass, and
  its UMAP (352 s) and Harmony (138 s) are the stock in-memory ones. BPCells
  re-evaluates its lazy chain on every pass (PCA 703 s, UMAP 749 s).
- **Against baseline in-memory Scanpy** at 500k, the largest size it survives:
  bixverse from h5ad is 2.7x faster without tSNE (111 s against 297 s) at under
  half the memory (6.5 GB against 14.2 GB). Scanpy only wins the load.
- **scrapper is fast wherever it stays in C++.** Best QC, HVG and default tSNE
  at 100k, but the loaders, the R harmony package and a UMAP that rebuilds the
  kNN cost it, and the in-memory path runs out of room at 500k from mtx.
- **The GPU earns its keep from 500k.** 62 s without tSNE at 500k and 124 s on
  the full data. tSNE is now most of every run that has it (FFT on the GPU: 35
  s at 500k, 90 s on the full data), so dropping it from a large-data workflow
  is the smart call.
