# Results

Seconds per step, one repeat each. **OOM** marks the step where the container
was killed; **TIMEOUT** where no step finished for 45 min. Peak GB is cgroup
anon memory over the whole run, tSNE included; the bixverse GPU and MLX
columns (\*) are the native macOS peak memory footprint, close to but not
the same metric. On-disk store GB is what
a run leaves in its scratch volume. Setup, versions and caveats:
[methods](methods.md).

Regenerate the timing tables with `uv run scripts/tables.py results <dataset>`
and the quality scores with `uv run scripts/score.py results/<dataset> data/<dataset>`.
The raw per-run files are in `results/<dataset>/<run>/`: step times
(`steps.csv`), memory samples (`mem.csv`), the run log, disk use and the
scores (`quality.csv` per data set). Embeddings, clusters and markers are not
committed; a rerun writes them.

qd: quick and dirty. `tsne_quick` is the qdtsne Barnes-Hut (theta 1, 500
iterations, depth-capped tree), not a standard Barnes-Hut tSNE.
`cluster_fast` is Leiden on k-means centroids, labels handed back to the
cells. Neither counts towards the totals.

Scanpy dask has no DGE step (Wilcoxon fails on Dask arrays), so its totals
miss the step that costs in-memory Scanpy 46 to 602 s. It is an experimental
path; see [methods](methods.md#caveats).

## Simulation

Splat data with 24 batches, 12 groups and uneven group composition per batch,
fitted to the PBMC data ([methods](methods.md#data)). Stack: bixverse 0.8.1,
bixverse.gpu 0.6.1, manifoldsR 0.5.0, Scanpy 1.12.4, scrapper 1.6.3, Seurat
5.6.0, CyteArc 1.3.0.

![Time without tSNE and peak memory on the simulation](figures/scaling_splat.png)

![Wall time per step on the simulation, scaled per step](figures/steps_heatmap_splat.png)

### 100k cells (96,342 after QC)

| step | bixverse mtx | bixverse h5ad | bixverse GPU* | bixverse MLX* | Scanpy mtx | Scanpy h5ad | Scanpy dask | scrapper mtx | scrapper h5ad | scrapper HDF5 | Seurat std mtx | Seurat std h5ad | Seurat BPCells | CyteArc mtx | CyteArc h5ad |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| load | 9.7 | 5.4 | 5.1 | 4.6 | 17.8 | 2.3 | 5.1 | 34.2 | 4.8 | 46.7 | 36.5 | 8.5 | 13.3 | 32.3 | 11.1 |
| qc | 0.1 | 0.1 | 0.2 | 0.1 | 0.6 | 0.6 | 0.9 | 0.4 | 0.4 | 1.3 | 2.6 | 2.7 | 1.1 | 0.0 | 0.0 |
| normalise | n/a | n/a | n/a | n/a | 2.0 | 1.9 | 0.0 | 0.1 | 0.1 | 0.0 | 0.2 | 0.2 | 0.4 | 2.8 | 2.9 |
| hvg | 0.4 | 0.3 | 0.3 | 0.2 | 1.4 | 1.4 | 1.4 | 0.1 | 0.1 | 3.8 | 3.7 | 3.8 | 2.9 | 2.2 | 2.3 |
| pca | 0.8 | 0.8 | 0.9 | 0.5 | 2.2 | 2.2 | 3.9 | 2.0 | 2.0 | 13.1 | 10.3 | 10.5 | 58.2 | 6.0 | 6.1 |
| harmony | 0.5 | 0.5 | 1.0 | 0.3 | 0.5 | 0.5 | 0.4 | 12.1 | 14.2 | 12.2 | 13.3 | 13.5 | 13.8 | 13.7 | 13.1 |
| knn_snn | 2.7 | 2.7 | 1.9 | 1.5 | 26.9 | 26.5 | 24.2 | 6.5 | 6.3 | 6.8 | 7.5 | 7.6 | 7.9 | 24.3 | 23.6 |
| cluster | 0.9 | 1.0 | 0.8 | 0.8 | 3.0 | 2.7 | 2.7 | 15.4 | 13.3 | 12.6 | 19.9 | 19.9 | 20.6 | 13.9 | 13.9 |
| cluster_fast (qd) | 1.0 | 1.0 | 0.4 | 0.4 | n/a | n/a | n/a | 17.7 | 17.3 | 17.5 | n/a | n/a | n/a | n/a | n/a |
| umap | 3.8 | 3.6 | 0.9 | 0.8 | 39.0 | 37.7 | 37.8 | 37.5 | 38.1 | 38.4 | 45.8 | 46.7 | 47.4 | 84.4 | 84.2 |
| dge | 0.6 | 0.6 | 0.7 | 0.5 | 47.4 | 46.1 | - | 3.3 | 3.3 | 81.5 | 10.8 | 11.1 | 57.0 | 6.3 | 6.2 |
| tsne_default | 43.3 | 42.8 | 37.4 | 34.2 | 161.7 | 167.1 | 154.7 | n/a | n/a | n/a | 125.5 | 125.1 | 141.8 | n/a | n/a |
| tsne_fft | 14.6 | 14.8 | 3.2 | 3.1 | 37.8 | 38.4 | 35.8 | n/a | n/a | n/a | 32.8 | 32.6 | 32.0 | n/a | n/a |
| tsne_quick (qd) | 10.8 | 11.2 | 4.6 | 3.4 | n/a | n/a | n/a | 20.0 | 21.0 | 20.6 | n/a | n/a | n/a | n/a | n/a |
| **total** | **88** | **84** | **57** | **50** | **340** | **327** | **267** | **132** | **104** | **237** | **309** | **282** | **397** | **186** | **164** |
| total without tSNE | 19 | 15 | 12 | 9 | 141 | 122 | 77 | 112 | 83 | 216 | 151 | 125 | 223 | 186 | 164 |
| **peak GB** | **1.6** | **1.6** | **1.9** | **1.5** | **4.8** | **2.6** | **1.8** | **5.5** | **5.5** | **3.3** | **8.9** | **8.9** | **2.5** | **7.7** | **8.3** |
| peak swap GB | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| on-disk store GB | 0.3 | 0.3 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 1.2 | 0.8 | 0.8 |

### 500k cells (482,409 after QC)

| step | bixverse mtx | bixverse h5ad | bixverse GPU* | bixverse MLX* | Scanpy mtx | Scanpy h5ad | Scanpy dask | scrapper mtx | scrapper h5ad | scrapper HDF5 | Seurat std mtx | Seurat std h5ad | Seurat BPCells | CyteArc mtx | CyteArc h5ad |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| load | 48.1 | 29.4 | 21.0 | 19.0 | **OOM** | 11.4 | 20.7 | 203.2 | 18.4 | 227.7 | 215.5 | 34.9 | 64.8 | 156.0 | 36.9 |
| qc | 0.3 | 0.2 | 0.3 | 0.3 | - | 2.8 | 3.8 | 2.2 | 2.2 | 6.3 | 13.4 | 13.4 | 4.0 | 0.0 | 0.0 |
| normalise | n/a | n/a | n/a | n/a | - | 3.6 | 0.0 | 0.4 | 0.4 | 0.0 | 0.8 | 0.9 | 1.9 | 12.7 | 13.0 |
| hvg | 1.0 | 1.1 | 0.7 | 0.7 | - | 3.2 | 4.4 | 0.5 | 0.5 | 19.2 | 19.1 | 19.5 | 12.8 | 7.2 | 7.2 |
| pca | 2.3 | 2.3 | 1.3 | 1.1 | - | 10.4 | 10.8 | 14.9 | 14.9 | 71.2 | **OOM** | **OOM** | 273.6 | 22.6 | 27.5 |
| harmony | 1.7 | 1.6 | 1.1 | 0.7 | - | 2.2 | 2.0 | 100.1 | 83.3 | 83.7 | - | - | 87.8 | 72.4 | 80.6 |
| knn_snn | 14.2 | 13.9 | 7.5 | 6.7 | - | 32.7 | 29.5 | 40.4 | 40.0 | 41.7 | - | - | 45.2 | 145.0 | 159.3 |
| cluster | 4.1 | 4.0 | 3.2 | 3.1 | - | 19.5 | 19.8 | 114.9 | 122.8 | 103.3 | - | - | 133.2 | 16.2 | 16.2 |
| cluster_fast (qd) | 14.4 | 14.2 | 3.1 | 2.5 | n/a | n/a | n/a | 196.3 | 194.4 | 196.7 | n/a | n/a | n/a | n/a | n/a |
| umap | 35.0 | 33.5 | 3.9 | 3.7 | - | 226.2 | 226.2 | 181.6 | 175.4 | 178.2 | - | - | 256.8 | 421.0 | 422.9 |
| dge | 2.3 | 2.3 | 1.8 | 1.9 | - | 454.2 | - | 22.4 | 22.7 | 1716.6 | - | - | 259.7 | 13.3 | 13.0 |
| tsne_default | 252.5 | 251.5 | 222.8 | 225.3 | - | 1315.2 | 1319.4 | n/a | n/a | n/a | - | - | 1389.9 | n/a | n/a |
| tsne_fft | 62.7 | 61.3 | 13.8 | 20.4 | - | 152.7 | 155.6 | n/a | n/a | n/a | - | - | 156.4 | n/a | n/a |
| tsne_quick (qd) | 41.7 | 48.2 | 27.1 | 23.3 | n/a | n/a | n/a | 131.8 | 133.4 | 135.0 | n/a | n/a | n/a | n/a | n/a |
| **total** | **466** | **449** | **305** | **306** | failed | **2234** | **1792** | **812** | **614** | **2583** | failed | failed | **2686** | **866** | **777** |
| total without tSNE | 109 | 88 | 41 | 37 | failed | 766 | 317 | 681 | 481 | 2448 | failed | failed | 1140 | 866 | 777 |
| **peak GB** | **5.7** | **5.7** | **5.4** | **6.1** | **22.1** | **14.2** | **7.8** | **22.6** | **22.7** | **12.3** | **22.8** | **22.8** | **6.9** | **9.6** | **11.4** |
| peak swap GB | 0.0 | 0.0 | 0.0 | 0.0 | 4.0 | 0.0 | 0.0 | 2.8 | 2.6 | 0.0 | 3.7 | 3.7 | 0.0 | 0.0 | 0.0 |
| on-disk store GB | 1.4 | 1.4 | 1.4 | 1.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 6.2 | 4.1 | 4.1 |

### 1M cells (964,763 after QC)

| step | bixverse mtx | bixverse h5ad | bixverse GPU* | bixverse MLX* | Scanpy mtx | Scanpy h5ad | Scanpy dask | scrapper mtx | scrapper h5ad | scrapper HDF5 | Seurat std mtx | Seurat std h5ad | Seurat BPCells | CyteArc mtx | CyteArc h5ad |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| load | 89.5 | 56.7 | 48.6 | 41.6 | **OOM** | **OOM** | 39.3 | **OOM** | **OOM** | 405.2 | **OOM** | **OOM** | 129.0 | 302.6 | 66.9 |
| qc | 0.5 | 0.4 | 0.4 | 0.4 | - | - | 7.2 | - | - | 12.5 | - | - | 8.5 | 0.1 | 0.1 |
| normalise | n/a | n/a | n/a | n/a | - | - | 0.0 | - | - | 0.0 | - | - | 4.1 | 27.3 | 28.1 |
| hvg | 2.1 | 2.3 | 1.6 | 1.5 | - | - | 8.2 | - | - | 37.6 | - | - | 24.5 | 12.7 | 13.6 |
| pca | 4.8 | 5.2 | 2.6 | 2.1 | - | - | 18.2 | - | - | 143.6 | - | - | 463.0 | 49.8 | 54.5 |
| harmony | 3.2 | 3.0 | 2.0 | 1.2 | - | - | 4.2 | - | - | 166.0 | - | - | 175.1 | 163.2 | 148.4 |
| knn_snn | 29.2 | 29.7 | 15.2 | 13.4 | - | - | 39.6 | - | - | 86.7 | - | - | 94.8 | 364.3 | 392.8 |
| cluster | 8.2 | 8.2 | 6.7 | 6.5 | - | - | 46.8 | - | - | 269.1 | - | - | 342.7 | 19.3 | 19.6 |
| cluster_fast (qd) | 45.7 | 47.0 | 7.9 | 6.3 | n/a | n/a | n/a | - | - | 544.6 | n/a | n/a | n/a | n/a | n/a |
| umap | 80.2 | 80.4 | 10.6 | 9.7 | - | - | 555.3 | - | - | 361.8 | - | - | 545.8 | 863.0 | 868.9 |
| dge | 4.1 | 4.2 | 3.6 | 3.3 | - | - | - | - | - | **TIMEOUT** | - | - | 517.6 | 24.0 | 24.5 |
| tsne_default | 654.2 | 628.0 | 562.5 | 544.3 | - | - | **TIMEOUT** | n/a | n/a | n/a | - | - | **TIMEOUT** | n/a | n/a |
| tsne_fft | 193.8 | 197.3 | 29.5 | 45.6 | - | - | - | n/a | n/a | n/a | - | - | - | n/a | n/a |
| tsne_quick (qd) | 134.0 | 133.7 | 84.2 | 72.5 | n/a | n/a | n/a | - | - | - | n/a | n/a | n/a | n/a | n/a |
| **total** | **1204** | **1149** | **768** | **742** | failed | failed | failed | failed | failed | failed | failed | failed | failed | **1826** | **1617** |
| total without tSNE | 222 | 190 | 91 | 80 | failed | failed | 719 | failed | failed | failed | failed | failed | 2305 | 1826 | 1617 |
| **peak GB** | **11.5** | **10.5** | **10.9** | **10.9** | **22.3** | **22.0** | **10.8** | **22.8** | **22.9** | **22.5** | **22.9** | **22.9** | **10.8** | **10.0** | **10.3** |
| peak swap GB | 0.0 | 0.0 | 0.0 | 0.0 | 3.9 | 3.9 | 0.0 | 3.7 | 3.3 | 1.3 | 3.5 | 3.3 | 0.0 | 0.0 | 0.0 |
| on-disk store GB | 2.7 | 2.7 | 2.7 | 2.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 12.5 | 8.3 | 8.3 |

### Quality

Against the truth, h5ad paths, Scanpy Dask and BPCells as they are. Purity
is the share of the 15 nearest neighbours in the same true group; rare is the
smallest group (about 1%, in 6 of 24 batches). (qd) columns score
`cluster_fast` at resolution 1. DGE R-precision is against markers detectable
in at least 10% of their group, and on the genes every tool reported
(shared). Definitions in [methods](methods.md#quality-scores).

#### 100k

| tool | clusters | ARI | NMI | rare F1 | ARI (qd) | rare F1 (qd) | HVG prec. | Harmony purity | rare purity | batch mix | UMAP purity | tSNE purity | tSNE (qd) purity | DGE R-prec. | DGE R-prec. shared |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| bixverse | 11 | 0.976 | 0.958 | 0.261 | 0.869 | 0.274 | 0.430 | 0.970 | 0.260 | 0.990 | 0.973 | 0.975 | 0.976 | 0.895 | 0.975 |
| bixverse GPU | 11 | 0.977 | 0.956 | 0.235 | 0.858 | 0.263 | 0.430 | 0.968 | 0.226 | 1.010 | 0.972 | 0.974 | 0.975 | 0.895 | 0.975 |
| bixverse MLX | 11 | 0.974 | 0.955 | 0.218 | 0.857 | 0.262 | 0.430 | 0.967 | 0.222 | 1.011 | 0.970 | 0.973 | 0.974 | 0.895 | 0.975 |
| Scanpy | 11 | 0.884 | 0.855 | 0.091 | - | - | 0.390 | 0.908 | 0.130 | 0.993 | 0.917 | 0.922 | - | 0.927 | 0.881 |
| Scanpy dask | 10 | 0.909 | 0.873 | 0.095 | - | - | 0.390 | 0.908 | 0.130 | 0.993 | 0.916 | 0.922 | - | - | - |
| scrapper | 9 | 0.942 | 0.943 | 0.132 | 0.937 | 0.130 | 0.439 | 0.928 | 0.169 | 0.968 | 0.933 | - | 0.933 | 0.939 | 0.896 |
| scrapper HDF5 | 9 | 0.942 | 0.944 | 0.133 | 0.935 | 0.129 | 0.439 | 0.929 | 0.165 | 0.968 | 0.934 | - | 0.930 | 0.939 | 0.896 |
| Seurat std | 13 | 0.812 | 0.911 | 0.269 | - | - | 0.430 | 0.971 | 0.268 | 0.989 | 0.972 | 0.978 | - | 0.876 | 0.975 |
| Seurat BPCells | 13 | 0.788 | 0.907 | 0.270 | - | - | 0.430 | 0.971 | 0.268 | 0.989 | 0.972 | 0.978 | - | 0.876 | 0.975 |
| CyteArc | 10 | 0.954 | 0.925 | 0.144 | - | - | 0.366 | 0.949 | 0.120 | 0.972 | 0.954 | - | - | 0.927 | 0.881 |

#### 500k

| tool | clusters | ARI | NMI | rare F1 | ARI (qd) | rare F1 (qd) | HVG prec. | Harmony purity | rare purity | batch mix | UMAP purity | tSNE purity | tSNE (qd) purity | DGE R-prec. | DGE R-prec. shared |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| bixverse | 12 | 0.883 | 0.932 | 0.297 | 0.865 | 0.314 | 0.426 | 0.969 | 0.291 | 0.982 | 0.974 | 0.978 | 0.979 | 0.894 | 0.976 |
| bixverse GPU | 13 | 0.796 | 0.904 | 0.281 | 0.789 | 0.284 | 0.426 | 0.965 | 0.262 | 1.004 | 0.970 | 0.972 | 0.974 | 0.894 | 0.976 |
| bixverse MLX | 12 | 0.869 | 0.928 | 0.307 | 0.807 | 0.284 | 0.426 | 0.967 | 0.268 | 1.004 | 0.971 | 0.975 | 0.976 | 0.894 | 0.976 |
| Scanpy | 12 | 0.777 | 0.826 | 0.110 | - | - | 0.398 | 0.894 | 0.131 | 0.984 | 0.907 | 0.916 | - | 0.934 | 0.883 |
| Scanpy dask | 11 | 0.871 | 0.852 | 0.108 | - | - | 0.398 | 0.894 | 0.131 | 0.984 | 0.906 | 0.916 | - | - | - |
| scrapper | 9 | 0.944 | 0.946 | 0.136 | 0.940 | 0.134 | 0.440 | 0.928 | 0.184 | 0.961 | 0.934 | - | 0.918 | 0.940 | 0.905 |
| scrapper HDF5 | 9 | 0.943 | 0.945 | 0.135 | 0.939 | 0.133 | 0.440 | 0.927 | 0.185 | 0.961 | 0.933 | - | 0.921 | 0.940 | 0.905 |
| Seurat BPCells | 15 | 0.702 | 0.878 | 0.315 | - | - | 0.428 | 0.970 | 0.309 | 0.981 | 0.972 | 0.980 | - | 0.694 | 0.966 |
| CyteArc | 10 | 0.962 | 0.937 | 0.169 | - | - | 0.393 | 0.954 | 0.159 | 0.970 | 0.960 | - | - | 0.934 | 0.883 |

#### 1M

| tool | clusters | ARI | NMI | rare F1 | ARI (qd) | rare F1 (qd) | HVG prec. | Harmony purity | rare purity | batch mix | UMAP purity | tSNE purity | tSNE (qd) purity | DGE R-prec. | DGE R-prec. shared |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| bixverse | 13 | 0.788 | 0.911 | 0.351 | 0.874 | 0.347 | 0.436 | 0.969 | 0.292 | 0.982 | 0.974 | 0.977 | 0.979 | 0.897 | 0.975 |
| bixverse GPU | 13 | 0.797 | 0.906 | 0.292 | 0.861 | 0.279 | 0.436 | 0.963 | 0.231 | 1.006 | 0.969 | 0.972 | 0.973 | 0.897 | 0.975 |
| bixverse MLX | 12 | 0.867 | 0.929 | 0.302 | 0.862 | 0.291 | 0.436 | 0.965 | 0.237 | 1.005 | 0.970 | 0.973 | 0.974 | 0.897 | 0.975 |
| Scanpy dask | 12 | 0.859 | 0.834 | 0.107 | - | - | 0.396 | 0.889 | 0.118 | 0.986 | 0.904 | - | - | - | - |
| Seurat BPCells | 14 | 0.764 | 0.898 | 0.345 | - | - | 0.437 | 0.968 | 0.281 | 0.982 | 0.971 | - | - | 0.628 | 0.912 |
| CyteArc | 11 | 0.974 | 0.947 | 0.344 | - | - | 0.396 | 0.956 | 0.169 | 0.965 | 0.963 | - | - | 0.934 | 0.879 |

### Harmony on the same input

bixverse's PCA (30 PCs) and the true batch labels for every
implementation, native, 8 threads, median of 3 runs. Extra GB is peak RSS over
a load-only run. kNN overlap is the share of the 15 nearest neighbours each
cell keeps against harmonypy; purity, rare purity and batch mix as in the
quality tables. The input PCA scores purity 0.964, rare purity 0.516 and batch
mix 0.156 at 1M (0.965, 0.487, 0.183 at 100k).

| implementation | 100k s | 1M s | 100k extra GB | 1M extra GB | kNN overlap 100k / 1M | purity 1M | rare purity 1M | batch mix 1M |
|---|---|---|---|---|---|---|---|---|
| bixverse v2 | **0.24** | 2.11 | 0.27 | 2.50 | 0.966 / 0.971 | 0.969 | 0.292 | 0.982 |
| bixverse v2, `block_size = 0.05` | 0.29 | 2.28 | 0.27 | 2.56 | 0.966 / 0.971 | 0.969 | 0.292 | 0.982 |
| bixverse GPU (wgpu) | 0.30 | 1.66 | 0.25 | 1.71 | 0.967 / 0.969 | 0.969 | 0.291 | 0.982 |
| bixverse MLX | 0.25 | **1.00** | 0.20 | 1.35 | 0.967 / 0.971 | 0.969 | 0.292 | 0.982 |
| bixverse v1 | 0.38 | 3.33 | 0.26 | 2.47 | 0.753 / 0.712 | 0.966 | 0.256 | 1.005 |
| harmonypy 2.1.0 | 0.44 | 4.16 | 0.15 | 1.44 | 1 / 1 | 0.968 | 0.282 | 0.982 |

Inside the pipeline (Docker) bixverse's `harmony_v2_sc` takes 0.5 s at 100k,
1.6 s at 500k and 3.0 s at 1M; the gap to the standalone numbers is the R
wrapper plus the VM, not split further.

### What it shows

- **bixverse is about 5x faster than scrapper, at a quarter of its memory at
  500k.** From h5ad without tSNE: 15 s against 83 s at 100k, 88 s against
  481 s at 500k (5.7 GB against 22.7 GB). Against in-memory Scanpy 8.1x and
  8.7x (122 and 766 s). Scanpy on Dask comes closest (77, 317 and 719 s), but
  without DGE.
- **At 1M only the out-of-core designs survive.** bixverse (190 s from h5ad),
  Scanpy Dask (719 s, no DGE), CyteArc (1,617 s) and Seurat BPCells (2,305 s). scrapper makes
  500k at the memory ceiling with 2.8 GB swap; Seurat standard OOMs in PCA at
  500k.
- **From 500k the GPU rows halve that again.** 41 s (wgpu) and 37 s (MLX) at
  500k, 91 s and 80 s at 1M, native and uncapped; at 100k 12 and 9 s against
  15 s. Most of the gain is UMAP (80 s to 10 to 11 s at 1M), then the kNN
  (30 s to 13 to 15 s). Load is 8 to 15 s faster too, partly because native
  I/O skips the VM. Leiden and DGE are the same CPU code.
- **Embeddings: bixverse and Seurat lead, Scanpy trails.** Harmony purity
  0.968 to 0.971 for both at every size, the GPU rows 0.963 to 0.968, CyteArc
  0.949 to 0.956, scrapper 0.926 to 0.929, Scanpy 0.889 to 0.908. UMAP and
  tSNE keep the order.
- **The GPU rows mix slightly more and keep less of the rare group.** Batch
  mix 1.004 to 1.011 against 0.982 to 0.990 on the CPU, and rare purity 0.22
  to 0.27 against 0.26 to 0.29; the gap is widest at 1M (0.23 against 0.29).
  Harmony is not the cause: on the same input
  the GPU and MLX Harmony score as v2 does (rare purity 0.291 and 0.292, batch
  mix 0.982 at 1M). Which upstream step it is, is not checked.
- **Clustering: CyteArc wins ARI from 500k.** 0.954, 0.962 and 0.974 at
  100k, 500k and 1M with 10, 10 and 11 clusters, Leiden on its fuzzy
  connectivity graph. It merges the rare group up to 500k (rare F1 0.14 and
  0.17) and finds it at 1M (0.34). scrapper gives 0.94 at 100k and 500k (it
  has no scores at 1M) with 9 clusters for 12 groups, from its rank-weighted
  sNN without pruning; it merges groups, so its rare F1 stays at 0.13.
  bixverse leads at 100k (0.976, 11 clusters). At 500k and 1M every bixverse row gives 12 or 13 clusters,
  and ARI follows the count: about 0.87 to 0.88 with 12, 0.79 to 0.80 with
  13. Which rows land on 13 is not stable (rare F1, purity and batch mix do
  not move with it). Seurat 0.70 to 0.81.
- **The rare group goes to Seurat and bixverse.** Rare F1 0.26 to 0.35 for
  both on the CPU, against 0.09 to 0.13 for Scanpy and scrapper; CyteArc
  0.14 to 0.17, then 0.34 at 1M. Nobody
  recovers it well: the best-matching cluster is still mostly other cells.
- **`cluster_fast` does not pay off on the CPU here.** It keeps the rare group
  (bixverse rare F1 within 0.02 of Leiden) at ARI 0.79 to 0.94, but the CPU
  k-means costs more than the Leiden it replaces: 14 s against 4 s at 500k and
  47 s against 8 s at 1M for bixverse, 194 s against 123 s for scrapper. On
  the GPU and MLX rows it is about Leiden's time.
- **DGE: bixverse in seconds.** 0.5 to 4.2 s against 3.3 to 23 s for scrapper,
  6 to 25 s for CyteArc, 46 to 454 s for Scanpy and 57 to 518 s for BPCells (including a one-off
  transpose of its data layer, see [methods](methods.md#caveats)). On the shared genes
  bixverse and Seurat agree at 100k and 500k (R-precision 0.97 to 0.975;
  BPCells drops to 0.91 at 1M); on detectable markers
  scrapper, Scanpy and CyteArc rank slightly better (0.93 to 0.94 against
  0.89 to 0.90). bixverse's `min_prop = 0.05` reports fewer genes, so its all-gene
  AUROC is lower (0.735 against 0.88 to 0.94 at 500k): markers it filters out
  rank last. BPCells drops to 0.69 and 0.63 at 500k and 1M; why is not
  checked.
- **tSNE: bixverse on the CPU is 2x to 6x faster in every category, the GPU
  FFT up to 11x.** Standard
  Barnes-Hut at 500k: 252 s against 1,315 s for Scanpy and 1,390 s for
  BPCells, both of which time out at 1M. FFT: 61 s on the CPU and 14 to 20 s
  on the GPU, against 153 to 156 s. Quick and dirty: 42 to 48 s against
  scrapper's 133 s, both qdtsne with the leaf approximation. From 500k
  bixverse's CPU tSNE uses an approximate kNN where Scanpy's
  and Seurat's default Barnes-Hut pay for an exact one
  ([methods](methods.md#workflow)).
- **tSNE sets bixverse's CPU peak at 1M.** Before tSNE the CPU rows peak at
  8.3 GB; the run peak is 10.5 (h5ad) and 11.5 GB (mtx). At 500k tSNE
  adds 0.1 to 0.2 GB.
- **scrapper HDF5 trades time for memory, up to 500k.** 216 s and 3.3 GB at
  100k against 83 s and 5.5 GB in memory; 2,448 s and 12.3 GB without swap at
  500k against 481 s and 22.7 GB with 2.6 GB swap. Same scores. DGE is most of
  the gap (82 s against 3.3 s at 100k, 1,717 s against 23 s at 500k), then the
  DelayedArray pre-filter in load (228 s at 500k). At 1M it gets past load
  (405 s) but peaks at 22.5 GB and times out in DGE. Why DGE is this
  slow on the HDF5 matrix is not profiled. PBMC shows the same: 203 s and
  2.7 GB at 100k against 70 s and 4.8 GB, and a DGE timeout on the full
  data.
- **Disk: bixverse's store is the smallest.** It takes 0.3, 1.4 and 2.7 GB,
  about three quarters of the BPCells store (0.4, 1.8, 3.7 GB in a load-only
  run) and a third of the 8.1 GB h5ad it reads at 1M. The BPCells column in
  the tables is larger (1.2, 6.2, 12.5 GB) because it also holds the
  gene-major copy of the normalised data its DGE step writes. CyteArc's store
  holds the counts cell- and gene-major: 0.8, 4.1 and 8.3 GB.
- **CyteArc runs every size at about 10 GB, slowly.** From h5ad 164, 777 and
  1,617 s; its import sets the peak (8.3, 11.4 and 10.3 GB) and the analysis
  stays under 6 GB. The analysis scales about linearly (153, 740 and
  1,550 s). UMAP is about half of it: 84 s at 100k against 38 s for Scanpy,
  863 to 869 s at 1M. Slower than every in-memory row at 100k, level with
  in-memory Scanpy at 500k (777 against 766 s), 1.4x faster than BPCells at
  1M. Loading from mtx costs 21 to 236 s more than from h5ad.
- **Harmony: bixverse v2 is 2x faster than harmonypy 2.1.0 on the same
  input, MLX 4.2x, at the same result.** 2.11 and 1.00 s against 4.16 s at
  1M; v2, GPU and MLX keep 97% of harmonypy's neighbours and match its purity
  and batch mix, with slightly more of the rare group (0.29 against 0.28).
  harmonypy needs 1.1 GB less than v2 at 1M, about the same as MLX. v1 keeps
  only 71 to 75% of the neighbours and mixes more.

## PBMC

Parse 1M PBMC and random subsamples, the same stack as the simulation. On PBMC
the DGE groups are the 24 samples.

![Time without tSNE and peak memory on PBMC](figures/scaling_pbmc.png)

![Wall time per step on PBMC, scaled per step](figures/steps_heatmap_pbmc.png)

### 100k cells (69,412 after QC)

| step | bixverse mtx | bixverse h5ad | bixverse GPU* | bixverse MLX* | Scanpy mtx | Scanpy h5ad | Scanpy dask | scrapper mtx | scrapper h5ad | scrapper HDF5 | Seurat std mtx | Seurat std h5ad | Seurat BPCells | CyteArc mtx | CyteArc h5ad |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| load | 10.0 | 5.9 | 5.1 | 4.9 | 19.4 | 2.3 | 6.1 | 37.0 | 5.1 | 74.3 | 41.0 | 8.9 | 14.5 | 42.7 | 20.4 |
| qc | 0.6 | 0.8 | 0.4 | 0.3 | 0.7 | 0.8 | 1.1 | 0.4 | 0.4 | 1.1 | 2.7 | 2.6 | 1.2 | 0.1 | 0.1 |
| normalise | n/a | n/a | n/a | n/a | 2.0 | 1.9 | 0.0 | 0.1 | 0.1 | 0.0 | 0.1 | 0.2 | 0.5 | 3.5 | 3.5 |
| hvg | 0.4 | 0.4 | 0.2 | 0.2 | 1.3 | 1.4 | 1.7 | 0.2 | 0.2 | 2.8 | 4.0 | 4.0 | 4.0 | 4.9 | 5.0 |
| pca | 0.6 | 0.5 | 0.4 | 0.3 | 1.4 | 1.4 | 4.0 | 2.3 | 2.4 | 9.9 | 6.9 | 7.3 | 74.7 | 4.8 | 4.7 |
| harmony | 0.6 | 0.6 | 0.7 | 0.4 | 0.6 | 0.6 | 0.5 | 12.2 | 13.6 | 12.6 | 13.5 | 13.3 | 14.0 | 25.9 | 25.3 |
| knn_snn | 2.0 | 2.1 | 1.1 | 1.1 | 27.0 | 26.9 | 23.7 | 4.4 | 4.4 | 4.4 | 5.3 | 5.4 | 5.6 | 16.7 | 16.4 |
| cluster | 0.8 | 0.9 | 0.7 | 0.7 | 2.0 | 2.0 | 1.9 | 8.4 | 9.3 | 8.6 | 17.8 | 17.8 | 18.1 | 14.4 | 14.4 |
| cluster_fast (qd) | 0.7 | 0.8 | 0.4 | 0.3 | n/a | n/a | n/a | 10.4 | 10.6 | 10.5 | n/a | n/a | n/a | n/a | n/a |
| umap | 2.5 | 2.7 | 0.6 | 0.5 | 26.8 | 26.6 | 26.4 | 28.1 | 28.0 | 28.2 | 34.7 | 34.8 | 35.3 | 59.0 | 59.0 |
| dge | 0.7 | 0.8 | 0.6 | 0.6 | 55.7 | 51.9 | - | 6.0 | 6.3 | 61.3 | 15.4 | 15.2 | 118.2 | 8.9 | 9.1 |
| tsne_default | 25.8 | 25.7 | 25.5 | 24.7 | 96.1 | 94.6 | 102.3 | n/a | n/a | n/a | 67.0 | 71.8 | 75.9 | n/a | n/a |
| tsne_fft | 7.8 | 7.7 | 2.3 | 2.2 | 31.9 | 32.0 | 31.0 | n/a | n/a | n/a | 23.9 | 24.6 | 24.2 | n/a | n/a |
| tsne_quick (qd) | 4.5 | 4.8 | 2.9 | 2.8 | n/a | n/a | n/a | 14.0 | 15.3 | 14.5 | n/a | n/a | n/a | n/a | n/a |
| **total** | **56** | **53** | **41** | **39** | **265** | **242** | **199** | **113** | **85** | **218** | **232** | **206** | **386** | **181** | **158** |
| total without tSNE | 18 | 15 | 10 | 9 | 137 | 116 | 65 | 99 | 70 | 203 | 141 | 109 | 286 | 181 | 158 |
| **peak GB** | **1.6** | **1.7** | **2.2** | **1.4** | **6.0** | **2.0** | **1.6** | **5.2** | **4.8** | **2.7** | **7.7** | **7.8** | **2.5** | **8.0** | **9.1** |
| peak swap GB | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| on-disk store GB | 0.3 | 0.3 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 1.2 | 0.8 | 0.8 |

### 500k cells (346,259 after QC)

| step | bixverse mtx | bixverse h5ad | bixverse GPU* | bixverse MLX* | Scanpy mtx | Scanpy h5ad | Scanpy dask | scrapper mtx | scrapper h5ad | scrapper HDF5 | Seurat std mtx | Seurat std h5ad | Seurat BPCells | CyteArc mtx | CyteArc h5ad |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| load | 46.2 | 25.0 | 20.9 | 20.6 | **OOM** | 11.9 | 22.9 | **OOM** | 18.9 | 371.7 | **OOM** | **OOM** | 70.7 | 222.9 | 78.1 |
| qc | 1.8 | 1.7 | 1.2 | 1.2 | - | 3.8 | 4.0 | - | 2.1 | 5.6 | - | - | 4.6 | 0.1 | 0.1 |
| normalise | n/a | n/a | n/a | n/a | - | 3.5 | 0.0 | - | 0.4 | 0.0 | - | - | 2.3 | 14.0 | 14.1 |
| hvg | 1.1 | 1.1 | 0.8 | 0.8 | - | 3.2 | 5.0 | - | 0.9 | 13.3 | - | - | 14.2 | 17.7 | 18.1 |
| pca | 2.2 | 2.0 | 1.0 | 0.8 | - | 5.7 | 9.8 | - | 14.4 | 50.5 | - | - | 352.1 | 18.4 | 20.1 |
| harmony | 2.1 | 2.3 | 1.3 | 0.8 | - | 2.4 | 2.3 | - | 87.1 | 124.8 | - | - | 88.9 | 153.0 | 144.5 |
| knn_snn | 11.5 | 11.5 | 5.8 | 5.4 | - | 30.7 | 27.2 | - | 27.1 | 28.6 | - | - | 31.2 | 69.8 | 76.1 |
| cluster | 4.0 | 4.1 | 3.3 | 3.3 | - | 14.1 | 13.0 | - | 85.4 | 82.6 | - | - | 104.3 | 15.0 | 15.2 |
| cluster_fast (qd) | 11.9 | 12.1 | 1.9 | 1.6 | n/a | n/a | n/a | - | 117.5 | 118.8 | n/a | n/a | n/a | n/a | n/a |
| umap | 22.0 | 22.2 | 2.6 | 2.5 | - | 155.0 | 152.9 | - | 127.9 | 126.8 | - | - | 198.3 | 293.3 | 293.4 |
| dge | 2.8 | 2.9 | 2.4 | 2.3 | - | 602.2 | - | - | 39.2 | 1401.2 | - | - | 554.8 | 23.3 | 23.3 |
| tsne_default | 151.1 | 154.0 | 136.4 | 134.6 | - | 795.5 | 806.3 | n/a | n/a | n/a | - | - | 587.7 | n/a | n/a |
| tsne_fft | 39.0 | 38.0 | 9.5 | 13.8 | - | 109.3 | 109.3 | n/a | n/a | n/a | - | - | 105.7 | n/a | n/a |
| tsne_quick (qd) | 24.5 | 24.9 | 15.0 | 13.5 | n/a | n/a | n/a | - | 84.1 | 87.2 | n/a | n/a | n/a | n/a | n/a |
| **total** | **308** | **290** | **200** | **200** | failed | **1737** | **1153** | failed | **488** | **2292** | failed | failed | **2115** | **828** | **683** |
| total without tSNE | 94 | 73 | 39 | 38 | failed | 832 | 237 | failed | 403 | 2205 | failed | failed | 1421 | 828 | 683 |
| **peak GB** | **6.3** | **6.6** | **5.9** | **5.9** | **22.2** | **14.2** | **6.7** | **22.8** | **20.9** | **8.3** | **22.8** | **22.9** | **5.6** | **8.5** | **9.6** |
| peak swap GB | 0.0 | 0.0 | 0.0 | 0.0 | 3.6 | 0.0 | 0.0 | 3.7 | 0.0 | 0.0 | 3.7 | 3.6 | 0.0 | 0.0 | 0.0 |
| on-disk store GB | 1.3 | 1.3 | 1.3 | 1.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 5.8 | 3.9 | 3.9 |

### Full data set (684,932 after QC)

| step | bixverse mtx | bixverse h5ad | bixverse GPU* | bixverse MLX* | Scanpy mtx | Scanpy h5ad | Scanpy dask | scrapper mtx | scrapper h5ad | scrapper HDF5 | Seurat std mtx | Seurat std h5ad | Seurat BPCells | CyteArc mtx | CyteArc h5ad |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| load | 98.5 | 48.1 | 43.3 | 41.1 | **OOM** | **OOM** | 40.2 | **OOM** | **OOM** | 731.4 | **OOM** | **OOM** | 141.6 | 384.1 | 143.1 |
| qc | 3.1 | 3.2 | 2.1 | 2.0 | - | - | 7.4 | - | - | 13.1 | - | - | 9.4 | 0.1 | 0.1 |
| normalise | n/a | n/a | n/a | n/a | - | - | 0.0 | - | - | 0.0 | - | - | 4.6 | 26.5 | 27.9 |
| hvg | 2.0 | 2.0 | 1.7 | 1.6 | - | - | 8.5 | - | - | 27.4 | - | - | 27.0 | 32.5 | 32.0 |
| pca | 4.3 | 4.0 | 2.1 | 1.7 | - | - | 16.9 | - | - | 106.2 | - | - | 695.6 | 38.5 | 41.0 |
| harmony | 3.7 | 3.8 | 2.3 | 1.1 | - | - | 4.5 | - | - | 254.9 | - | - | 217.4 | 227.7 | 239.6 |
| knn_snn | 24.5 | 24.6 | 12.5 | 11.5 | - | - | 33.4 | - | - | 60.6 | - | - | 70.0 | 166.9 | 171.5 |
| cluster | 8.7 | 8.8 | 6.9 | 6.6 | - | - | 30.2 | - | - | 217.2 | - | - | 255.5 | 17.1 | 17.0 |
| cluster_fast (qd) | 36.6 | 36.9 | 4.9 | 3.8 | n/a | n/a | n/a | - | - | 330.3 | n/a | n/a | n/a | n/a | n/a |
| umap | 51.8 | 51.2 | 5.8 | 5.2 | - | - | 348.8 | - | - | 261.7 | - | - | 454.0 | 588.5 | 588.0 |
| dge | 5.1 | 5.3 | 4.6 | 4.3 | - | - | - | - | - | **TIMEOUT** | - | - | 1136.6 | 39.3 | 39.9 |
| tsne_default | 371.8 | 376.0 | 323.4 | 321.3 | - | - | 1941.0 | n/a | n/a | n/a | - | - | 1605.9 | n/a | n/a |
| tsne_fft | 115.6 | 115.4 | 19.8 | 30.8 | - | - | 246.5 | n/a | n/a | n/a | - | - | 231.6 | n/a | n/a |
| tsne_quick (qd) | 81.7 | 83.4 | 40.8 | 41.7 | n/a | n/a | n/a | - | - | - | n/a | n/a | n/a | n/a | n/a |
| **total** | **771** | **726** | **465** | **469** | failed | failed | **2678** | failed | failed | failed | failed | failed | **4849** | **1521** | **1300** |
| total without tSNE | 202 | 151 | 81 | 75 | failed | failed | 490 | failed | failed | failed | failed | failed | 3012 | 1521 | 1300 |
| **peak GB** | **9.5** | **8.7** | **8.5** | **8.0** | **22.4** | **22.5** | **10.4** | **22.9** | **22.9** | **15.8** | **22.9** | **22.9** | **10.9** | **8.4** | **8.8** |
| peak swap GB | 0.0 | 0.0 | 0.0 | 0.0 | 3.9 | 3.9 | 0.0 | 3.2 | 3.1 | 0.0 | 3.1 | 3.6 | 0.0 | 0.0 | 0.0 |
| on-disk store GB | 2.6 | 2.6 | 2.6 | 2.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 11.5 | 7.7 | 7.7 |

### Warm start

Reconnecting to data a cold run already converted (`WARM=1 scripts/run.sh`),
load step only. bixverse reopens its store and the stored cell map, so its
object holds the post-QC cells; BPCells reopens the pre-filtered, pre-QC matrix
and builds the Seurat object. Each warm run goes straight after its cold run,
so the files are likely still in the page cache. Warm peak GB is the load only;
cold load s is the mtx load step of the full cold run.

![Cold against warm load for bixverse and Seurat + BPCells](figures/warm_start.png)

| data | framework | cold load s | warm load s | warm peak GB |
|---|---|---|---|---|
| PBMC 100k | bixverse | 10.0 | 0.3 | 0.2 |
| PBMC 100k | Seurat BPCells | 14.5 | 2.3 | 0.8 |
| PBMC 500k | bixverse | 46.2 | 0.4 | 0.3 |
| PBMC 500k | Seurat BPCells | 70.1 | 10.1 | 0.9 |
| PBMC full | bixverse | 98.5 | 0.6 | 0.3 |
| PBMC full | Seurat BPCells | 142.6 | 20.9 | 1.1 |
| splat 1M | bixverse | 89.5 | 0.7 | 0.4 |
| splat 1M | Seurat BPCells | 132.5 | 21.2 | 1.0 |

### What it shows

![Speed-up per step against in-memory Scanpy at 500k](figures/speedup_vs_scanpy_500k.png)

![Speed-up per step against Scanpy with Dask on the full data set](figures/speedup_vs_scanpy_dask_full.png)

- **The real data agree with the simulation.** Four frameworks finish the
  full set, all out-of-core: bixverse in 151 s from h5ad (202 s from mtx;
  81 s and 75 s on wgpu and MLX), Scanpy Dask in 490 s without DGE, CyteArc
  in 1,300 s (1,521 s from mtx), Seurat + BPCells in 3,012 s. Everything that holds the counts in memory dies at
  load.
- **Memory is close among the CPU survivors.** Full data peaks: CyteArc 8.4
  GB (mtx) and 8.8 GB (h5ad), bixverse 8.7 GB (h5ad) and 9.5 GB (mtx),
  Scanpy Dask 10.4 GB, Seurat + BPCells 10.9 GB.
- **Each out-of-core design pays somewhere else.** bixverse pays up front to
  convert into its store (48 s from h5ad on the full data) and is fast
  after. Dask loads in 40 s, but its UMAP (349 s) is the stock in-memory one
  and it skips DGE. BPCells re-evaluates its lazy chain on every pass (PCA
  696 s, UMAP 454 s) and its DGE takes 1,137 s, the transpose to gene-major
  order included (11.5 GB on disk in all). CyteArc also converts up front
  (143 s from h5ad, 384 s from mtx, 7.7 GB on disk), then spends 588 s in
  UMAP and 228 to 240 s in Harmony.
- **Against in-memory Scanpy** at 500k, the largest size it survives: bixverse
  from h5ad is 11x faster without tSNE (73 s against 832 s) at under half the
  memory (6.6 GB against 14.2 GB). DGE is 602 s of Scanpy's 832 s. CyteArc
  from h5ad passes it too (683 s at 9.6 GB), on DGE: without it CyteArc
  needs 660 s against Scanpy's 230 s.
- **A warm start removes the conversion cost.** On the full data bixverse
  reconnects in 0.6 s at 0.3 GB, Seurat + BPCells in 20.9 s at 1.1 GB. The
  BPCells PCA and UMAP cost above is untouched by a warm start.
- **The GPU earns its keep from 500k.** 39 s (wgpu) and 38 s (MLX) without
  tSNE at 500k, 81 and 75 s on the full data, against 73 and 151 s on the
  CPU. The FFT tSNE takes 20 to 31 s on the full data against 115 s on the
  CPU; tSNE is now most of every bixverse run.
- **scrapper out of core does not finish the full data.** On HDF5 it gets
  through load (731 s) to UMAP at a 15.8 GB peak without swap, then times out
  in DGE, as on the 1M simulation. At 500k it finishes in 2,205 s at 8.3 GB.
