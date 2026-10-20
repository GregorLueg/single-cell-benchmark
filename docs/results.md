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

qd: quick and dirty. `tsne_quick` is the qdtsne Barnes-Hut (theta 1, 500
iterations, depth-capped tree), not a standard Barnes-Hut tSNE.
`cluster_fast` is Leiden on k-means centroids, labels handed back to the
cells. Neither counts towards the totals.

Scanpy dask has no DGE step (Wilcoxon fails on Dask arrays), so its totals
miss the step that costs in-memory Scanpy 46 to 602 s. It is an experimental
path; see [methods](methods.md#caveats).

## Simulation

Splat data with 24 batches, 12 groups and uneven group composition per batch,
fitted to the PBMC data ([methods](methods.md#data)). Stack: bixverse 0.8.0,
bixverse.gpu 0.5.0, manifoldsR 0.5.0, Scanpy 1.12.4, scrapper 1.6.3, Seurat
5.6.0.

![Time without tSNE and peak memory on the simulation](figures/scaling_splat.png)

![Wall time per step on the simulation, scaled per step](figures/steps_heatmap_splat.png)

### 100k cells (96,342 after QC)

| step | bixverse mtx | bixverse h5ad | bixverse GPU* | bixverse MLX* | Scanpy mtx | Scanpy h5ad | Scanpy dask | scrapper mtx | scrapper h5ad | scrapper HDF5 | Seurat std mtx | Seurat std h5ad | Seurat BPCells |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| load | 10.3 | 5.8 | 5.0 | 5.0 | 17.8 | 2.3 | 5.1 | 34.4 | 6.1 | 47.1 | 37.9 | 9.4 | 13.3 |
| qc | 0.1 | 0.1 | 0.1 | 0.1 | 0.6 | 0.6 | 0.9 | 0.5 | 0.5 | 1.4 | 2.6 | 2.7 | 1.1 |
| normalise | n/a | n/a | n/a | n/a | 2.0 | 1.9 | 0.0 | 0.1 | 0.1 | 0.0 | 0.2 | 0.2 | 0.4 |
| hvg | 0.3 | 0.3 | 0.3 | 0.2 | 1.4 | 1.4 | 1.4 | 0.1 | 0.1 | 3.8 | 3.7 | 3.8 | 2.9 |
| pca | 1.5 | 1.5 | 0.6 | 0.5 | 2.2 | 2.2 | 3.9 | 1.8 | 1.8 | 5.1 | 10.6 | 10.6 | 58.3 |
| harmony | 0.5 | 0.5 | 0.4 | 0.3 | 0.5 | 0.5 | 0.4 | 12.2 | 14.4 | 14.3 | 13.3 | 13.3 | 13.8 |
| knn_snn | 2.8 | 2.8 | 1.7 | 1.5 | 26.9 | 26.5 | 24.2 | 6.4 | 6.4 | 6.7 | 7.5 | 7.6 | 7.8 |
| cluster | 0.9 | 1.2 | 0.8 | 0.8 | 3.0 | 2.7 | 2.7 | 13.2 | 13.9 | 12.6 | 19.0 | 19.3 | 20.7 |
| cluster_fast (qd) | 1.0 | 1.0 | 0.4 | 0.4 | n/a | n/a | n/a | 17.5 | 17.5 | 17.3 | n/a | n/a | n/a |
| umap | 3.8 | 3.7 | 0.9 | 0.7 | 39.0 | 37.7 | 37.8 | 43.1 | 43.6 | 43.0 | 45.7 | 46.3 | 46.3 |
| dge | 0.5 | 0.5 | 0.5 | 0.5 | 47.4 | 46.1 | - | 3.4 | 3.5 | 79.3 | 11.8 | 10.8 | 88.7 |
| tsne_default | 41.4 | 42.1 | 34.7 | 34.6 | 161.7 | 167.1 | 154.7 | n/a | n/a | n/a | 125.1 | 122.4 | 146.7 |
| tsne_fft | 14.9 | 15.0 | 3.2 | 2.8 | 37.8 | 38.4 | 35.8 | n/a | n/a | n/a | 31.6 | 31.6 | 32.9 |
| tsne_quick (qd) | 11.1 | 11.1 | 3.8 | 3.5 | n/a | n/a | n/a | 25.1 | 24.8 | 23.5 | n/a | n/a | n/a |
| **total** | **88** | **85** | **52** | **51** | **340** | **327** | **267** | **140** | **115** | **237** | **309** | **278** | **433** |
| total without tSNE | 21 | 16 | 10 | 10 | 141 | 122 | 77 | 115 | 90 | 213 | 152 | 124 | 253 |
| **peak GB** | **1.5** | **1.7** | **2.0** | **1.5** | **4.8** | **2.6** | **1.8** | **5.6** | **5.6** | **3.4** | **8.9** | **8.9** | **2.6** |
| peak swap GB | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| on-disk store GB | 1.3 | 1.3 | 1.3 | 1.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.4 |

### 500k cells (482,409 after QC)

| step | bixverse mtx | bixverse h5ad | bixverse GPU* | bixverse MLX* | Scanpy mtx | Scanpy h5ad | Scanpy dask | scrapper mtx | scrapper h5ad | scrapper HDF5 | Seurat std mtx | Seurat std h5ad | Seurat BPCells |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| load | 44.2 | 27.8 | 25.5 | 22.9 | **OOM** | 11.4 | 20.7 | 204.8 | 23.0 | 224.1 | 224.8 | 41.1 | 66.1 |
| qc | 0.3 | 0.2 | 0.3 | 0.3 | - | 2.8 | 3.8 | 2.2 | 2.2 | 6.3 | 13.6 | 13.4 | 4.0 |
| normalise | n/a | n/a | n/a | n/a | - | 3.6 | 0.0 | 0.4 | 0.4 | 0.0 | 0.9 | 0.8 | 1.9 |
| hvg | 0.7 | 0.8 | 0.7 | 0.6 | - | 3.2 | 4.4 | 0.5 | 0.5 | 18.6 | 19.4 | 19.4 | 12.7 |
| pca | 3.6 | 3.8 | 1.3 | 1.7 | - | 10.4 | 10.8 | 13.6 | 13.7 | 30.7 | **OOM** | **OOM** | 271.2 |
| harmony | 1.7 | 1.7 | 1.1 | 0.6 | - | 2.2 | 2.0 | 100.0 | 84.0 | 82.0 | - | - | 87.8 |
| knn_snn | 13.7 | 13.7 | 7.3 | 6.6 | - | 32.7 | 29.5 | 39.8 | 39.6 | 40.1 | - | - | 45.3 |
| cluster | 4.0 | 4.0 | 3.3 | 3.2 | - | 19.5 | 19.8 | 115.7 | 109.8 | 101.6 | - | - | 131.8 |
| cluster_fast (qd) | 14.1 | 14.9 | 3.1 | 2.5 | n/a | n/a | n/a | 196.1 | 194.2 | 195.2 | n/a | n/a | n/a |
| umap | 33.2 | 33.4 | 3.8 | 3.5 | - | 226.2 | 226.2 | 212.5 | 219.5 | 212.9 | - | - | 255.5 |
| dge | 1.8 | 1.9 | 1.7 | 1.7 | - | 454.2 | - | 22.2 | 22.2 | 1709.8 | - | - | 404.3 |
| tsne_default | 246.5 | 244.9 | 216.6 | 211.0 | - | 1315.2 | 1319.4 | n/a | n/a | n/a | - | - | 1404.1 |
| tsne_fft | 63.5 | 60.9 | 13.3 | 19.9 | - | 152.7 | 155.6 | n/a | n/a | n/a | - | - | 156.8 |
| tsne_quick (qd) | 41.1 | 41.4 | 25.2 | 22.8 | n/a | n/a | n/a | 154.8 | 152.1 | 153.4 | n/a | n/a | n/a |
| **total** | **454** | **434** | **300** | **295** | failed | **2234** | **1792** | **866** | **667** | **2580** | failed | failed | **2842** |
| total without tSNE | 103 | 87 | 45 | 41 | failed | 766 | 317 | 712 | 515 | 2426 | failed | failed | 1281 |
| **peak GB** | **5.7** | **5.8** | **5.6** | **6.2** | **22.1** | **14.2** | **7.8** | **22.6** | **22.7** | **12.4** | **22.8** | **22.8** | **6.5** |
| peak swap GB | 0.0 | 0.0 | 0.0 | 0.0 | 4.0 | 0.0 | 0.0 | 2.7 | 2.6 | 0.0 | 3.6 | 3.7 | 0.0 |
| on-disk store GB | 6.6 | 6.6 | 6.6 | 6.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 1.8 |

### 1M cells (964,763 after QC)

| step | bixverse mtx | bixverse h5ad | bixverse GPU* | bixverse MLX* | Scanpy mtx | Scanpy h5ad | Scanpy dask | scrapper mtx | scrapper h5ad | scrapper HDF5 | Seurat std mtx | Seurat std h5ad | Seurat BPCells |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| load | 96.8 | 72.5 | 57.1 | 43.6 | **OOM** | **OOM** | 39.3 | **OOM** | **OOM** | 415.2 | **OOM** | **OOM** | 132.5 |
| qc | 0.5 | 1.2 | 0.4 | 0.4 | - | - | 7.2 | - | - | 13.1 | - | - | 9.8 |
| normalise | n/a | n/a | n/a | n/a | - | - | 0.0 | - | - | 0.0 | - | - | 4.3 |
| hvg | 1.4 | 1.6 | 1.2 | 1.1 | - | - | 8.2 | - | - | 38.4 | - | - | 24.8 |
| pca | 6.6 | 6.8 | 2.3 | 3.2 | - | - | 18.2 | - | - | 68.3 | - | - | 467.9 |
| harmony | 3.1 | 3.0 | 1.9 | 1.2 | - | - | 4.2 | - | - | 169.9 | - | - | 178.6 |
| knn_snn | 28.7 | 29.1 | 14.9 | 13.2 | - | - | 39.6 | - | - | 91.9 | - | - | 99.7 |
| cluster | 8.0 | 8.4 | 6.5 | 6.2 | - | - | 46.8 | - | - | 275.5 | - | - | 367.4 |
| cluster_fast (qd) | 44.7 | 45.7 | 8.0 | 6.2 | n/a | n/a | n/a | - | - | 554.8 | n/a | n/a | n/a |
| umap | 79.1 | 78.3 | 10.3 | 9.8 | - | - | 555.3 | - | - | 436.0 | - | - | 554.7 |
| dge | 3.2 | 3.3 | 5.4 | 2.9 | - | - | - | - | - | **TIMEOUT** | - | - | 822.0 |
| tsne_default | 640.9 | 643.5 | 525.4 | 525.5 | - | - | **TIMEOUT** | n/a | n/a | n/a | - | - | **TIMEOUT** |
| tsne_fft | 195.4 | 193.2 | 29.2 | 45.1 | - | - | - | n/a | n/a | n/a | - | - | - |
| tsne_quick (qd) | 136.0 | 133.7 | 71.6 | 72.8 | n/a | n/a | n/a | - | - | - | n/a | n/a | n/a |
| **total** | **1200** | **1174** | **726** | **725** | failed | failed | failed | failed | failed | failed | failed | failed | failed |
| total without tSNE | 227 | 204 | 100 | 81 | failed | failed | 719 | failed | failed | failed | failed | failed | 2662 |
| **peak GB** | **11.5** | **10.5** | **10.3** | **11.0** | **22.3** | **22.0** | **10.8** | **22.7** | **22.8** | **22.3** | **22.8** | **22.8** | **9.5** |
| peak swap GB | 0.0 | 0.0 | 0.0 | 0.0 | 3.9 | 3.9 | 0.0 | 3.7 | 3.5 | 2.6 | 3.6 | 3.4 | 1.5 |
| on-disk store GB | 13.2 | 13.2 | 13.3 | 13.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 3.7 |

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
| bixverse GPU | 11 | 0.973 | 0.951 | 0.228 | 0.783 | 0.249 | 0.430 | 0.963 | 0.195 | 1.012 | 0.967 | 0.970 | 0.971 | 0.895 | 0.975 |
| bixverse MLX | 11 | 0.975 | 0.952 | 0.243 | 0.875 | 0.249 | 0.430 | 0.963 | 0.199 | 1.012 | 0.968 | 0.970 | 0.971 | 0.895 | 0.975 |
| Scanpy | 11 | 0.884 | 0.855 | 0.091 | - | - | 0.390 | 0.908 | 0.130 | 0.993 | 0.917 | 0.922 | - | 0.927 | 0.881 |
| Scanpy dask | 10 | 0.909 | 0.873 | 0.095 | - | - | 0.390 | 0.908 | 0.130 | 0.993 | 0.916 | 0.922 | - | - | - |
| scrapper | 9 | 0.944 | 0.945 | 0.133 | 0.938 | 0.130 | 0.439 | 0.929 | 0.170 | 0.968 | 0.934 | - | 0.935 | 0.939 | 0.896 |
| scrapper HDF5 | 9 | 0.945 | 0.946 | 0.134 | 0.937 | 0.129 | 0.439 | 0.929 | 0.169 | 0.968 | 0.934 | - | 0.935 | 0.939 | 0.896 |
| Seurat std | 13 | 0.812 | 0.911 | 0.269 | - | - | 0.430 | 0.971 | 0.268 | 0.989 | 0.972 | 0.978 | - | 0.876 | 0.975 |
| Seurat BPCells | 13 | 0.788 | 0.907 | 0.270 | - | - | 0.430 | 0.971 | 0.268 | 0.989 | 0.972 | 0.978 | - | 0.876 | 0.975 |

#### 500k

| tool | clusters | ARI | NMI | rare F1 | ARI (qd) | rare F1 (qd) | HVG prec. | Harmony purity | rare purity | batch mix | UMAP purity | tSNE purity | tSNE (qd) purity | DGE R-prec. | DGE R-prec. shared |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| bixverse | 12 | 0.879 | 0.931 | 0.303 | 0.865 | 0.297 | 0.426 | 0.969 | 0.291 | 0.982 | 0.973 | 0.978 | 0.978 | 0.894 | 0.976 |
| bixverse GPU | 22 | 0.863 | 0.923 | 0.255 | 0.920 | 0.244 | 0.426 | 0.964 | 0.226 | 1.005 | 0.968 | 0.971 | 0.973 | 0.894 | 0.976 |
| bixverse MLX | 22 | 0.889 | 0.931 | 0.280 | 0.824 | 0.278 | 0.426 | 0.966 | 0.240 | 1.004 | 0.971 | 0.974 | 0.975 | 0.894 | 0.976 |
| Scanpy | 12 | 0.777 | 0.826 | 0.110 | - | - | 0.398 | 0.894 | 0.131 | 0.984 | 0.907 | 0.916 | - | 0.934 | 0.883 |
| Scanpy dask | 11 | 0.871 | 0.852 | 0.108 | - | - | 0.398 | 0.894 | 0.131 | 0.984 | 0.906 | 0.916 | - | - | - |
| scrapper | 9 | 0.942 | 0.943 | 0.134 | 0.936 | 0.131 | 0.440 | 0.926 | 0.182 | 0.962 | 0.931 | - | 0.921 | 0.940 | 0.905 |
| scrapper HDF5 | 9 | 0.942 | 0.943 | 0.133 | 0.936 | 0.131 | 0.440 | 0.926 | 0.180 | 0.961 | 0.932 | - | 0.921 | 0.940 | 0.905 |
| Seurat BPCells | 15 | 0.702 | 0.878 | 0.315 | - | - | 0.428 | 0.970 | 0.309 | 0.981 | 0.972 | 0.980 | - | 0.694 | 0.966 |

#### 1M

| tool | clusters | ARI | NMI | rare F1 | ARI (qd) | rare F1 (qd) | HVG prec. | Harmony purity | rare purity | batch mix | UMAP purity | tSNE purity | tSNE (qd) purity | DGE R-prec. | DGE R-prec. shared |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| bixverse | 13 | 0.793 | 0.912 | 0.354 | 0.865 | 0.349 | 0.436 | 0.969 | 0.292 | 0.982 | 0.973 | 0.978 | 0.978 | 0.897 | 0.975 |
| bixverse GPU | 20 | 0.809 | 0.907 | 0.292 | 0.789 | 0.284 | 0.436 | 0.963 | 0.230 | 1.005 | 0.967 | 0.971 | 0.972 | 0.897 | 0.975 |
| bixverse MLX | 16 | 0.794 | 0.902 | 0.297 | 0.820 | 0.280 | 0.436 | 0.962 | 0.235 | 1.006 | 0.965 | 0.969 | 0.971 | 0.897 | 0.975 |
| Scanpy dask | 12 | 0.859 | 0.834 | 0.107 | - | - | 0.396 | 0.889 | 0.118 | 0.986 | 0.904 | - | - | - | - |
| Seurat BPCells | 14 | 0.764 | 0.898 | 0.345 | - | - | 0.437 | 0.968 | 0.281 | 0.982 | 0.971 | - | - | 0.628 | 0.912 |

### Harmony on the same input

bixverse 0.8.0's PCA (30 PCs) and the true batch labels for every
implementation, native, 8 threads, median of 3 runs. Extra GB is peak RSS over
a load-only run. kNN overlap is the share of the 15 nearest neighbours each
cell keeps against harmonypy; purity, rare purity and batch mix as in the
quality tables. The input PCA scores purity 0.964, rare purity 0.516 and batch
mix 0.156 at 1M (0.965, 0.487, 0.183 at 100k).

| implementation | 100k s | 1M s | 100k extra GB | 1M extra GB | kNN overlap 100k / 1M | purity 1M | rare purity 1M | batch mix 1M |
|---|---|---|---|---|---|---|---|---|
| bixverse v2 | **0.24** | 2.11 | 0.25 | 2.55 | 0.966 / 0.971 | 0.969 | 0.292 | 0.982 |
| bixverse v2, `block_size = 0.05` | 0.28 | 2.25 | 0.25 | 2.57 | 0.966 / 0.971 | 0.969 | 0.292 | 0.982 |
| bixverse GPU (wgpu) | 0.31 | 1.62 | 0.21 | 1.74 | 0.967 / 0.969 | 0.969 | 0.291 | 0.982 |
| bixverse MLX | 0.26 | **0.99** | 0.18 | 1.40 | 0.967 / 0.971 | 0.969 | 0.292 | 0.982 |
| bixverse v1 | 0.38 | 3.41 | 0.24 | 2.47 | 0.753 / 0.712 | 0.966 | 0.256 | 1.005 |
| harmonypy 2.1.0 | 0.44 | 4.16 | 0.15 | 1.45 | 1 / 1 | 0.968 | 0.282 | 0.982 |

Inside the pipeline (Docker) bixverse's `harmony_v2_sc` takes 0.5 s at 100k,
1.7 s at 500k and 3.0 s at 1M; the gap to the standalone numbers is the R
wrapper plus the VM, not split further.

### What it shows

- **bixverse is about 6x faster than scrapper, at a quarter of its memory at
  500k.** From h5ad without tSNE: 16 s against 90 s at 100k, 87 s against
  515 s at 500k (5.8 GB against 22.7 GB). Against in-memory Scanpy 7.6x and
  8.8x (122 and 766 s). Scanpy on Dask comes closest (77, 317 and 719 s), but
  without DGE.
- **At 1M only the out-of-core designs survive.** bixverse (204 s from h5ad),
  Scanpy Dask (719 s, no DGE) and Seurat BPCells (2,662 s). scrapper makes
  500k at the memory ceiling with 2.6 GB swap; Seurat standard OOMs in PCA at
  500k.
- **The GPU rows halve that again.** 45 s (wgpu) and 41 s (MLX) at 500k,
  100 s and 81 s at 1M, native and uncapped. Most of the gain is UMAP and the
  FFT tSNE; Leiden and DGE are the same CPU code.
- **Embeddings: bixverse and Seurat lead, Scanpy trails.** Harmony purity
  0.969 to 0.971 for both at every size, the GPU rows 0.962 to 0.966, scrapper
  0.926 to 0.929, Scanpy 0.889 to 0.908. UMAP and tSNE keep the order.
- **The GPU rows mix slightly more and keep less of the rare group.** Batch
  mix 1.004 to 1.012 against 0.982 to 0.990 on the CPU, and rare purity 0.20
  to 0.24 against 0.26 to 0.29. Harmony is not the cause: on the same input
  the GPU and MLX Harmony score as v2 does (rare purity 0.291 and 0.292, batch
  mix 0.982 at 1M). Which upstream step it is, is not checked.
- **Clustering: scrapper wins ARI from 500k.** 0.94 at every size with 9
  clusters for 12 groups, from its rank-weighted sNN without pruning; it
  merges groups, so its rare F1 stays at 0.13. bixverse leads at 100k (0.976,
  11 clusters) and falls to 0.79 to 0.90 at 500k and 1M with 12 to 13
  clusters. Seurat 0.70 to 0.81.
- **The rare group goes to Seurat and bixverse.** Rare F1 0.26 to 0.35 for
  both on the CPU, against 0.09 to 0.13 for Scanpy and scrapper.
- **`cluster_fast` does not pay off on the CPU here.** It keeps the rare group
  (bixverse rare F1 within 0.02 of Leiden) at ARI 0.78 to 0.98, but the CPU
  k-means costs more than the Leiden it replaces: 14 s against 4 s at 500k and
  45 s against 8 s at 1M for bixverse, 194 s against 110 s for scrapper. On
  the GPU and MLX rows it is about Leiden's time.
- **DGE: bixverse in seconds.** 0.5 to 5.4 s against 3.5 to 22 s for scrapper,
  46 to 454 s for Scanpy and 89 to 822 s for BPCells. On the shared genes
  bixverse and Seurat agree (R-precision 0.975); on detectable markers
  scrapper and Scanpy rank slightly better (0.93 to 0.94 against 0.89 to
  0.90). bixverse's `min_prop = 0.05` reports fewer genes, so its all-gene
  AUROC is lower (0.735 against 0.88 to 0.94 at 500k): markers it filters out
  rank last. BPCells drops to 0.69 and 0.63 at 500k and 1M; why is not
  checked.
- **tSNE: bixverse is 2x to 6x faster in every category.** Standard
  Barnes-Hut at 500k: 245 s against 1,315 s for Scanpy and 1,404 s for
  BPCells, both of which time out at 1M. FFT: 61 s on the CPU and 13 to 20 s
  on the GPU, against 153 to 157 s. Quick and dirty: 41 s against scrapper's
  152 s. From 500k bixverse's CPU tSNE uses an approximate kNN where Scanpy's
  and Seurat's default Barnes-Hut pay for an exact one
  ([methods](methods.md#workflow)).
- **tSNE sets bixverse's CPU peak at 1M.** Before tSNE the CPU rows peak at
  8.4 to 8.6 GB; the run peak is 10.5 (h5ad) and 11.5 GB (mtx). At 500k tSNE
  adds 0.1 GB.
- **scrapper HDF5 trades time for memory, up to 500k.** 213 s and 3.4 GB at
  100k against 90 s and 5.6 GB in memory; 2,426 s and 12.4 GB without swap at
  500k against 515 s and 22.7 GB with 2.6 GB swap. Same scores. DGE is most of
  the gap (79 s against 3.5 s at 100k, 1,710 s against 22 s at 500k), then the
  DelayedArray pre-filter in load (224 s at 500k). At 1M it gets past load
  (415 s) but peaks at 22.3 GB in Leiden and times out in DGE. Why DGE is this
  slow on the HDF5 matrix is not profiled.
- **Disk is bixverse's cost.** Its two on-disk views take 1.3, 6.6 and
  13.2 GB, about 3.6x BPCells (0.4, 1.8, 3.7 GB) and 1.6x the 8.1 GB h5ad it
  reads at 1M.
- **Harmony: bixverse v2 is 2x faster than harmonypy 2.1.0 on the same
  input, MLX 4.2x, at the same result.** 2.11 and 0.99 s against 4.16 s at
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

| step | bixverse mtx | bixverse h5ad | bixverse GPU* | bixverse MLX* | Scanpy mtx | Scanpy h5ad | Scanpy dask | scrapper mtx | scrapper h5ad | Seurat std mtx | Seurat std h5ad | Seurat BPCells |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| load | 10.4 | 6.0 | 5.8 | 5.5 | 19.4 | 2.3 | 6.1 | 38.1 | 6.5 | 42.6 | 10.2 | 14.5 |
| qc | 0.6 | 0.8 | 0.4 | 0.4 | 0.7 | 0.8 | 1.1 | 0.5 | 0.4 | 2.6 | 2.7 | 1.2 |
| normalise | n/a | n/a | n/a | n/a | 2.0 | 1.9 | 0.0 | 0.1 | 0.1 | 0.1 | 0.1 | 0.5 |
| hvg | 0.3 | 0.3 | 0.3 | 0.3 | 1.3 | 1.4 | 1.7 | 0.2 | 0.2 | 4.0 | 4.0 | 4.0 |
| pca | 1.3 | 1.2 | 0.5 | 0.4 | 1.4 | 1.4 | 4.0 | 1.7 | 1.7 | 7.1 | 6.3 | 73.1 |
| harmony | 0.6 | 0.6 | 0.6 | 0.4 | 0.6 | 0.6 | 0.5 | 12.3 | 12.2 | 13.2 | 13.3 | 13.7 |
| knn_snn | 2.1 | 2.1 | 1.2 | 1.1 | 27.0 | 26.9 | 23.7 | 4.3 | 4.6 | 5.3 | 5.4 | 5.5 |
| cluster | 0.8 | 1.0 | 0.8 | 0.7 | 2.0 | 2.0 | 1.9 | 8.8 | 8.7 | 17.5 | 17.8 | 17.7 |
| cluster_fast (qd) | 0.8 | 0.8 | 0.4 | 0.4 | n/a | n/a | n/a | 10.2 | 10.6 | n/a | n/a | n/a |
| umap | 2.6 | 2.6 | 0.6 | 0.5 | 26.8 | 26.6 | 26.4 | 32.2 | 32.6 | 34.7 | 35.0 | 34.8 |
| dge | 0.7 | 0.7 | 0.6 | 0.6 | 55.7 | 51.9 | - | 6.2 | 6.3 | 15.4 | 15.5 | 196.2 |
| tsne_default | 25.7 | 26.0 | 24.1 | 23.7 | 96.1 | 94.6 | 102.3 | n/a | n/a | 66.4 | 71.2 | 71.2 |
| tsne_fft | 7.6 | 7.9 | 2.3 | 2.1 | 31.9 | 32.0 | 31.0 | n/a | n/a | 24.5 | 24.3 | 23.7 |
| tsne_quick (qd) | 4.6 | 4.8 | 3.2 | 2.8 | n/a | n/a | n/a | 17.0 | 18.4 | n/a | n/a | n/a |
| **total** | **57** | **54** | **40** | **39** | **265** | **242** | **199** | **121** | **92** | **234** | **206** | **456** |
| total without tSNE | 19 | 15 | 11 | 10 | 137 | 116 | 65 | 104 | 73 | 143 | 110 | 361 |
| **peak GB** | **1.6** | **1.7** | **2.2** | **1.5** | **6.0** | **2.0** | **1.6** | **5.3** | **4.9** | **7.7** | **7.8** | **2.6** |
| peak swap GB | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| on-disk store GB | 1.4 | 1.4 | 1.4 | 1.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.4 |

### 500k cells (346,259 after QC)

| step | bixverse mtx | bixverse h5ad | bixverse GPU* | bixverse MLX* | Scanpy mtx | Scanpy h5ad | Scanpy dask | scrapper mtx | scrapper h5ad | scrapper HDF5 | Seurat std mtx | Seurat std h5ad | Seurat BPCells |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| load | 55.0 | 27.2 | 30.1 | 23.4 | **OOM** | 11.9 | 22.9 | **OOM** | 162.0 | 365.5 | **OOM** | **OOM** | 70.1 |
| qc | 1.9 | 1.9 | 1.4 | 1.3 | - | 3.8 | 4.0 | - | 2.2 | 5.6 | - | - | 4.2 |
| normalise | n/a | n/a | n/a | n/a | - | 3.5 | 0.0 | - | 0.4 | 0.0 | - | - | 2.5 |
| hvg | 0.9 | 1.1 | 0.8 | 0.8 | - | 3.2 | 5.0 | - | 0.9 | 13.1 | - | - | 14.2 |
| pca | 2.5 | 2.4 | 0.9 | 1.3 | - | 5.7 | 9.8 | - | 10.1 | 21.7 | - | - | 349.9 |
| harmony | 2.1 | 2.2 | 1.3 | 0.6 | - | 2.4 | 2.3 | - | 87.1 | 123.6 | - | - | 92.4 |
| knn_snn | 11.0 | 11.5 | 5.8 | 5.2 | - | 30.7 | 27.2 | - | 26.5 | 28.2 | - | - | 33.0 |
| cluster | 4.0 | 4.1 | 3.3 | 3.1 | - | 14.1 | 13.0 | - | 89.0 | 76.7 | - | - | 111.3 |
| cluster_fast (qd) | 11.9 | 11.7 | 1.9 | 1.6 | n/a | n/a | n/a | - | 117.0 | 118.2 | n/a | n/a | n/a |
| umap | 21.5 | 21.8 | 2.6 | 2.4 | - | 155.0 | 152.9 | - | 150.3 | 152.0 | - | - | 197.6 |
| dge | 2.6 | 2.6 | 2.4 | 2.3 | - | 602.2 | - | - | 36.1 | 1395.8 | - | - | 953.5 |
| tsne_default | 149.7 | 149.2 | 132.0 | 129.3 | - | 795.5 | 806.3 | n/a | n/a | n/a | - | - | 598.0 |
| tsne_fft | 37.5 | 37.8 | 9.5 | 13.4 | - | 109.3 | 109.3 | n/a | n/a | n/a | - | - | 109.6 |
| tsne_quick (qd) | 24.5 | 24.8 | 14.2 | 13.5 | n/a | n/a | n/a | - | 95.7 | 100.8 | n/a | n/a | n/a |
| **total** | **313** | **287** | **204** | **197** | failed | **1737** | **1153** | failed | **660** | **2283** | failed | failed | **2536** |
| total without tSNE | 102 | 75 | 48 | 40 | failed | 832 | 237 | failed | 565 | 2182 | failed | failed | 1829 |
| **peak GB** | **6.3** | **6.5** | **6.1** | **6.1** | **22.2** | **14.2** | **6.7** | **22.7** | **22.9** | **8.3** | **22.8** | **22.9** | **5.6** |
| peak swap GB | 0.0 | 0.0 | 0.0 | 0.0 | 3.6 | 0.0 | 0.0 | 3.8 | 3.5 | 0.0 | 3.6 | 3.3 | 0.8 |
| on-disk store GB | 6.8 | 6.8 | 6.8 | 6.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 1.9 |

### Full data set (684,932 after QC)

| step | bixverse mtx | bixverse h5ad | bixverse GPU* | bixverse MLX* | Scanpy mtx | Scanpy h5ad | Scanpy dask | scrapper mtx | scrapper h5ad | Seurat std mtx | Seurat std h5ad | Seurat BPCells |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| load | 102.2 | 73.7 | 63.8 | 46.7 | **OOM** | **OOM** | 40.2 | **OOM** | **OOM** | **OOM** | **OOM** | 142.6 |
| qc | 3.6 | 4.4 | 2.5 | 2.3 | - | - | 7.4 | - | - | - | - | 9.4 |
| normalise | n/a | n/a | n/a | n/a | - | - | 0.0 | - | - | - | - | 4.6 |
| hvg | 1.6 | 1.7 | 1.5 | 1.4 | - | - | 8.5 | - | - | - | - | 27.0 |
| pca | 4.4 | 4.2 | 3.4 | 2.3 | - | - | 16.9 | - | - | - | - | 702.8 |
| harmony | 3.6 | 3.7 | 2.2 | 1.1 | - | - | 4.5 | - | - | - | - | 217.5 |
| knn_snn | 23.6 | 23.8 | 12.3 | 11.2 | - | - | 33.4 | - | - | - | - | 69.7 |
| cluster | 8.3 | 8.3 | 6.9 | 6.9 | - | - | 30.2 | - | - | - | - | 258.2 |
| cluster_fast (qd) | 37.9 | 39.2 | 4.8 | 3.8 | n/a | n/a | n/a | - | - | n/a | n/a | n/a |
| umap | 50.4 | 50.3 | 5.6 | 5.2 | - | - | 348.8 | - | - | - | - | 450.7 |
| dge | 4.6 | 4.7 | 4.2 | 4.1 | - | - | - | - | - | - | - | 1348.1 |
| tsne_default | 368.4 | 371.3 | 319.8 | 308.8 | - | - | 1941.0 | n/a | n/a | - | - | 1530.9 |
| tsne_fft | 116.3 | 113.6 | 20.0 | 19.3 | - | - | 246.5 | n/a | n/a | - | - | 228.9 |
| tsne_quick (qd) | 82.2 | 80.6 | 41.1 | 40.1 | n/a | n/a | n/a | - | - | n/a | n/a | n/a |
| **total** | **769** | **740** | **483** | **449** | failed | failed | **2678** | failed | failed | failed | failed | **4990** |
| total without tSNE | 202 | 175 | 102 | 81 | failed | failed | 490 | failed | failed | failed | failed | 3231 |
| **peak GB** | **9.5** | **8.9** | **8.8** | **8.3** | **22.4** | **22.5** | **10.4** | **22.7** | **22.7** | **22.7** | **22.8** | **9.5** |
| peak swap GB | 0.0 | 0.0 | 0.0 | 0.0 | 3.9 | 3.9 | 0.0 | 3.3 | 3.2 | 3.4 | 3.5 | 2.4 |
| on-disk store GB | 13.3 | 13.3 | 13.3 | 13.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 3.8 |

The bixverse MLX tSNE on the full data ran across a macOS DarkWake (the
machine was on caffeinate, which still allowed it); its time matches the wgpu
row (309 against 320 s), so it is kept.

### Warm start

Reconnecting to data a cold run already converted (`WARM=1 scripts/run.sh`),
load step only. bixverse reopens its two views and the stored cell map, so its
object holds the post-QC cells; BPCells reopens the pre-filtered, pre-QC matrix
and builds the Seurat object. Each warm run goes straight after its cold run,
so the files are likely still in the page cache. Warm peak GB is the load only;
cold load s is the mtx load step of the full cold run.

![Cold against warm load for bixverse and Seurat + BPCells](figures/warm_start.png)

| data | framework | cold load s | warm load s | warm peak GB |
|---|---|---|---|---|
| PBMC 100k | bixverse | 10.4 | 0.3 | 0.2 |
| PBMC 100k | Seurat BPCells | 14.5 | 2.3 | 0.8 |
| PBMC 500k | bixverse | 55.0 | 0.5 | 0.3 |
| PBMC 500k | Seurat BPCells | 70.1 | 10.1 | 0.9 |
| PBMC full | bixverse | 102.2 | 1.4 | 0.5 |
| PBMC full | Seurat BPCells | 142.6 | 20.9 | 1.1 |
| splat 1M | bixverse | 96.8 | 3.1 | 0.4 |
| splat 1M | Seurat BPCells | 132.5 | 21.2 | 1.0 |

### What it shows

![Speed-up per step against in-memory Scanpy at 500k](figures/speedup_vs_scanpy_500k.png)

![Speed-up per step against Scanpy with Dask on the full data set](figures/speedup_vs_scanpy_dask_full.png)

- **The real data agree with the simulation.** Three frameworks finish the
  full set, all out-of-core: bixverse in 175 s from h5ad (202 s from mtx;
  102 s and 81 s on wgpu and MLX), Scanpy Dask in 490 s without DGE, Seurat +
  BPCells in 3,231 s. Everything that holds the counts in memory dies at
  load.
- **Memory is a tie among the CPU survivors.** Full data peaks: bixverse 8.9
  GB (h5ad) and 9.5 GB (mtx), Scanpy Dask 10.4 GB, Seurat + BPCells 9.5 GB.
- **Each out-of-core design pays somewhere else.** bixverse pays up front to
  convert into its two views (74 s from h5ad on the full data) and is fast
  after. Dask loads in 40 s, but its UMAP (349 s) is the stock in-memory one
  and it skips DGE. BPCells re-evaluates its lazy chain on every pass (PCA
  703 s, UMAP 451 s) and its DGE takes 1,348 s.
- **Against in-memory Scanpy** at 500k, the largest size it survives: bixverse
  from h5ad is 11x faster without tSNE (75 s against 832 s) at under half the
  memory (6.5 GB against 14.2 GB). DGE is 602 s of Scanpy's 832 s.
- **A warm start removes the conversion cost.** On the full data bixverse
  reconnects in 1.4 s at 0.5 GB, Seurat + BPCells in 20.9 s at 1.1 GB. The
  BPCells PCA and UMAP cost above is untouched by a warm start.
- **The GPU earns its keep from 500k.** 48 s (wgpu) and 40 s (MLX) without
  tSNE at 500k, 102 and 81 s on the full data, against 75 and 175 s on the
  CPU. The FFT tSNE takes 19 to 20 s on the full data against 114 s on the
  CPU; tSNE is now most of every run that has it.
