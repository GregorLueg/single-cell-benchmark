# Results

Seconds per step, one repeat each. **OOM** marks the step where the container
was killed; **OOM (worker)** where a forked BiocParallel worker was;
**TIMEOUT** where a step ran past 30 min. Peak GB is cgroup anon memory; the
bixverse GPU column (\*) is native macOS RSS and not comparable. On-disk store
GB is what a run leaves in its scratch volume; `-` means not measured (the
in-memory tools write nothing). Setup, versions and caveats:
[methods](methods.md).

Regenerate the timing tables with `uv run scripts/tables.py results` and the
quality scores with `uv run scripts/score.py results/<dataset> data/<dataset>`.

qd: quick-and-dirty Barnes-Hut (qdtsne: theta 1, 500 iterations, depth-capped tree), not a standard Barnes-Hut tSNE.

## Simulation

Splat data with 24 batches, 12 groups and uneven group composition per batch,
fitted to the PBMC data ([methods](methods.md#data)). Current stack: bixverse
0.6.0, Seurat 5.6.0, harmonypy 2.1.0.

### 100k cells (96,342 after QC)

| step | bixverse mtx | bixverse h5ad | bixverse GPU* | Scanpy mtx | Scanpy h5ad | Scanpy dask | scrapper mtx | scrapper h5ad | Seurat std mtx | Seurat std h5ad | Seurat BPCells | OSCA HDF5 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| load | 9.8 | 6.0 | 5.4 | 17.6 | 2.6 | 5.2 | 35.9 | 6.5 | 38.8 | 9.8 | 13.3 | 32.3 |
| qc | 0.2 | 0.2 | 0.2 | 0.6 | 0.6 | 0.9 | 0.5 | 0.5 | 2.6 | 2.7 | 1.1 | 3.6 |
| normalise | n/a | n/a | n/a | 1.9 | 1.9 | 0.0 | 0.1 | 0.1 | 0.2 | 0.2 | 0.4 | 6.3 |
| hvg | 0.4 | 0.4 | 0.3 | 1.4 | 1.4 | 1.4 | 0.1 | 0.1 | 3.9 | 3.8 | 2.9 | 364.8 |
| pca | 1.7 | 1.7 | 0.6 | 2.2 | 2.2 | 3.9 | 2.2 | 2.2 | 10.4 | 10.6 | 58.2 | **OOM (worker)** |
| harmony | 0.5 | 0.5 | 0.6 | 0.5 | 0.5 | 0.5 | 12.9 | 15.1 | 13.9 | 13.4 | 14.3 | - |
| knn_snn | 2.1 | 2.2 | 1.1 | 27.2 | 27.5 | 24.6 | 7.2 | 7.1 | 7.8 | 7.6 | 8.0 | - |
| cluster | 1.0 | 1.2 | 0.9 | 2.9 | 2.9 | 2.9 | 15.4 | 16.5 | 20.4 | 19.1 | 21.4 | - |
| umap | 3.7 | 3.8 | 0.9 | 38.1 | 38.4 | 39.5 | 47.1 | 47.6 | 47.3 | 46.1 | 47.4 | - |
| dge | 0.5 | 0.5 | 0.5 | 46.8 | 46.6 | - | 3.9 | 3.8 | 11.0 | 10.7 | 87.9 | - |
| tsne_default | 45.8 | 44.8 | 37.1 | 169.0 | 166.5 | 160.5 | n/a | n/a | 128.6 | 122.0 | 144.8 | - |
| tsne_fft | 17.6 | 16.1 | 5.3 | 37.1 | 37.6 | 36.1 | n/a | n/a | 32.8 | 32.3 | 31.6 | n/a |
| tsne_quick (qd) | 12.2 | 11.9 | 3.9 | n/a | n/a | n/a | 28.7 | 27.0 | n/a | n/a | n/a | n/a |
| **total** | **96** | **90** | **57** | **345** | **329** | **276** | **154** | **127** | **318** | **278** | **431** | failed |
| total without tSNE | 20 | 17 | 11 | 139 | 125 | 79 | 125 | 100 | 156 | 124 | 255 | failed |
| **peak GB** | **1.5** | **1.5** | **4.1** | **4.7** | **3.0** | **2.4** | **5.4** | **5.4** | **8.9** | **8.9** | **2.5** | **22.5** |
| peak swap GB | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 3.9 |
| on-disk store GB | 1.3 | 1.3 | 1.3 | 0.0 | 0.0 | 0.0 | - | - | - | - | 0.4 | - |

### 500k cells (482,409 after QC)

| step | bixverse mtx | bixverse h5ad | bixverse GPU* | Scanpy mtx | Scanpy h5ad | Scanpy dask | scrapper mtx | scrapper h5ad | Seurat std mtx | Seurat std h5ad | Seurat BPCells |
|---|---|---|---|---|---|---|---|---|---|---|---|
| load | 59.8 | 29.7 | 24.5 | **OOM** | 14.2 | 20.5 | 193.6 | 23.1 | 219.0 | 41.1 | 65.0 |
| qc | 0.4 | 0.3 | 0.4 | - | 2.8 | 3.7 | 2.2 | 2.2 | 14.7 | 13.3 | 4.0 |
| normalise | n/a | n/a | n/a | - | 3.5 | 0.0 | 0.4 | 0.4 | 1.0 | 0.8 | 1.9 |
| hvg | 0.8 | 1.0 | 0.7 | - | 3.2 | 4.3 | 0.5 | 0.5 | 19.9 | 19.2 | 12.7 |
| pca | 4.7 | 4.7 | 2.2 | - | 10.4 | 10.5 | 13.6 | 13.7 | **OOM** | **OOM** | 272.8 |
| harmony | 1.7 | 1.7 | 1.3 | - | 2.1 | 2.1 | 84.2 | 99.6 | - | - | 87.6 |
| knn_snn | 10.7 | 10.4 | 4.5 | - | 33.5 | 30.1 | 40.1 | 39.8 | - | - | 44.8 |
| cluster | 5.6 | 5.3 | 4.1 | - | 20.3 | 20.6 | 118.4 | 116.5 | - | - | 128.0 |
| umap | 34.6 | 31.9 | 3.8 | - | 228.8 | 228.8 | 218.0 | 214.7 | - | - | 254.7 |
| dge | 1.9 | 1.9 | 2.4 | - | 450.3 | - | 22.5 | 22.1 | - | - | 396.2 |
| tsne_default | 265.3 | 255.5 | 219.8 | - | 1334.4 | 1345.4 | n/a | n/a | - | - | 1360.4 |
| tsne_fft | 67.8 | 62.0 | 25.6 | - | 156.9 | 151.5 | n/a | n/a | - | - | 155.9 |
| tsne_quick (qd) | 43.6 | 41.1 | 25.4 | n/a | n/a | n/a | 156.7 | 152.6 | n/a | n/a | n/a |
| **total** | **497** | **445** | **315** | failed | **2260** | **1817** | **850** | **685** | failed | failed | **2784** |
| total without tSNE | 120 | 87 | 44 | failed | 769 | 320 | 694 | 533 | failed | failed | 1268 |
| **peak GB** | **6.2** | **5.7** | **13.0** | **22.0** | **16.2** | **5.4** | **22.7** | **22.7** | **22.8** | **22.8** | **6.5** |
| peak swap GB | 0.0 | 0.0 | 0.0 | 3.8 | 0.0 | 0.0 | 2.6 | 2.6 | 3.7 | 3.7 | 0.0 |
| on-disk store GB | 6.6 | 6.6 | 6.6 | - | 0.0 | 0.0 | - | - | - | - | 1.8 |

### 1M cells (964,763 after QC)

| step | bixverse mtx | bixverse h5ad | bixverse GPU* | Scanpy mtx | Scanpy h5ad | Scanpy dask | scrapper mtx | scrapper h5ad | Seurat std mtx | Seurat std h5ad | Seurat BPCells |
|---|---|---|---|---|---|---|---|---|---|---|---|
| load | 117.4 | 81.4 | 62.3 | **OOM** | **OOM** | 42.3 | **OOM** | **OOM** | **OOM** | **OOM** | 133.3 |
| qc | 0.5 | 1.2 | 0.5 | - | - | 7.0 | - | - | - | - | 8.8 |
| normalise | n/a | n/a | n/a | - | - | 0.0 | - | - | - | - | 4.2 |
| hvg | 1.4 | 1.7 | 1.3 | - | - | 8.2 | - | - | - | - | 24.8 |
| pca | 8.7 | 9.4 | 3.8 | - | - | 18.5 | - | - | - | - | 468.2 |
| harmony | 3.0 | 3.0 | 2.1 | - | - | 4.2 | - | - | - | - | 176.0 |
| knn_snn | 21.8 | 22.6 | 11.6 | - | - | 39.8 | - | - | - | - | 100.8 |
| cluster | 9.7 | 10.3 | 8.4 | - | - | 47.9 | - | - | - | - | 354.3 |
| umap | 74.8 | 75.9 | 10.7 | - | - | 559.5 | - | - | - | - | 565.1 |
| dge | 3.2 | 3.4 | 7.5 | - | - | - | - | - | - | - | 800.4 |
| tsne_default | 642.3 | 629.9 | 536.2 | - | - | **TIMEOUT** | n/a | n/a | - | - | **TIMEOUT** |
| tsne_fft | 193.3 | 192.4 | 57.2 | - | - | - | n/a | n/a | - | - | - |
| tsne_quick (qd) | 137.3 | 134.1 | 76.3 | n/a | n/a | n/a | - | - | n/a | n/a | n/a |
| **total** | **1213** | **1165** | **778** | failed | failed | failed | failed | failed | failed | failed | failed |
| total without tSNE | 240 | 209 | 108 | failed | failed | 727 | failed | failed | failed | failed | 2636 |
| **peak GB** | **13.9** | **11.4** | **17.8** | **22.4** | **22.4** | **11.0** | **22.8** | **22.8** | **22.8** | **22.8** | **8.2** |
| peak swap GB | 0.0 | 0.0 | 0.0 | 3.4 | 3.7 | 0.0 | 3.7 | 3.3 | 3.6 | 3.5 | 1.7 |
| on-disk store GB | 13.2 | 13.2 | 13.3 | - | - | 0.0 | - | - | - | - | 3.7 |

### Quality

Against the truth, h5ad paths (mtx gives the same scores), Scanpy Dask at 1M.
Purity is the share of the 15 nearest neighbours in the same true group; rare
is the smallest group (about 1%, in 6 of 24 batches). DGE R-precision is
against markers detectable in at least 10% of their group, and on the genes
every tool reported (shared). Definitions in
[methods](methods.md#quality-scores).

#### 100k

| tool | clusters | ARI | NMI | rare F1 | HVG prec. | Harmony purity | rare purity | batch mix | UMAP purity | tSNE purity | tSNE (qd) purity | DGE R-prec. | DGE R-prec. shared |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| bixverse | 13 | 0.786 | 0.903 | 0.238 | 0.43 | 0.97 | 0.26 | 0.99 | 0.973 | 0.975 | 0.976 | 0.895 | 0.975 |
| bixverse GPU | 16 | 0.801 | 0.898 | 0.216 | 0.43 | 0.963 | 0.186 | 1.012 | 0.967 | 0.969 | 0.97 | 0.895 | 0.975 |
| Scanpy | 11 | 0.884 | 0.855 | 0.091 | 0.39 | 0.908 | 0.13 | 0.993 | 0.917 | 0.922 | - | 0.927 | 0.881 |
| Scanpy dask | 10 | 0.909 | 0.873 | 0.095 | 0.39 | 0.908 | 0.13 | 0.993 | 0.916 | 0.922 | - | - | - |
| scrapper | 9 | 0.942 | 0.944 | 0.133 | 0.439 | 0.928 | 0.17 | 0.968 | 0.933 | - | 0.932 | 0.939 | 0.896 |
| Seurat std | 13 | 0.812 | 0.911 | 0.269 | 0.43 | 0.971 | 0.268 | 0.989 | 0.972 | 0.978 | - | 0.876 | 0.975 |
| Seurat BPCells | 13 | 0.788 | 0.907 | 0.27 | 0.43 | 0.971 | 0.268 | 0.989 | 0.972 | 0.978 | - | 0.876 | 0.975 |

OSCA has no scores at 100k: its PCA worker was killed before anything was
written.

#### 500k

| tool | clusters | ARI | NMI | rare F1 | HVG prec. | Harmony purity | rare purity | batch mix | UMAP purity | tSNE purity | tSNE (qd) purity | DGE R-prec. | DGE R-prec. shared |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| bixverse | 23 | 0.868 | 0.917 | 0.29 | 0.426 | 0.969 | 0.291 | 0.982 | 0.973 | 0.978 | 0.979 | 0.894 | 0.976 |
| bixverse GPU | 71 | 0.818 | 0.9 | 0.265 | 0.426 | 0.965 | 0.235 | 1.005 | 0.969 | 0.972 | 0.974 | 0.894 | 0.976 |
| Scanpy | 12 | 0.777 | 0.826 | 0.11 | 0.398 | 0.894 | 0.131 | 0.984 | 0.907 | 0.916 | - | 0.934 | 0.883 |
| Scanpy dask | 11 | 0.871 | 0.852 | 0.108 | 0.398 | 0.894 | 0.131 | 0.984 | 0.906 | 0.916 | - | - | - |
| scrapper | 9 | 0.943 | 0.944 | 0.135 | 0.44 | 0.927 | 0.185 | 0.962 | 0.932 | - | 0.922 | 0.94 | 0.905 |
| Seurat BPCells | 15 | 0.702 | 0.878 | 0.315 | 0.428 | 0.97 | 0.309 | 0.981 | 0.972 | 0.98 | - | 0.694 | 0.966 |

#### 1M

| tool | clusters | ARI | NMI | rare F1 | HVG prec. | Harmony purity | rare purity | batch mix | UMAP purity | tSNE purity | tSNE (qd) purity | DGE R-prec. | DGE R-prec. shared |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| bixverse | 44 | 0.779 | 0.895 | 0.322 | 0.436 | 0.969 | 0.292 | 0.982 | 0.974 | 0.978 | 0.978 | 0.897 | 0.975 |
| bixverse GPU | 90 | 0.779 | 0.895 | 0.285 | 0.436 | 0.964 | 0.236 | 1.005 | 0.968 | 0.971 | 0.973 | 0.897 | 0.975 |
| Scanpy dask | 12 | 0.859 | 0.834 | 0.107 | 0.396 | 0.889 | 0.118 | 0.986 | 0.904 | - | - | - | - |
| Seurat BPCells | 14 | 0.764 | 0.898 | 0.345 | 0.437 | 0.968 | 0.281 | 0.982 | 0.971 | - | - | 0.628 | 0.912 |

### Harmony on the same input

bixverse 0.6.0's PCA (30 PCs) and the true batch labels for every
implementation, native, 8 threads, median of 3 runs. Extra GB is peak RSS over
a load-only run. kNN overlap is the share of each cell's 15 neighbours shared
with harmonypy's output. Uncorrected input: purity 0.965 / 0.964, rare purity
0.49 / 0.52, batch mix 0.18 / 0.16 (100k / 1M).

| implementation | 100k s | 1M s | 1M extra GB | kNN overlap (100k / 1M) | purity (1M) | rare purity (1M) | batch mix (1M) |
|---|---|---|---|---|---|---|---|
| bixverse v2 | **0.22** | 1.95 | 2.55 | 0.97 / 0.97 | 0.969 | 0.292 | 0.982 |
| bixverse v2, `block_size = 0.05` | 0.27 | 2.10 | 2.50 | 0.97 / 0.97 | 0.969 | 0.292 | 0.982 |
| bixverse GPU | 0.36 | **1.65** | 1.63 | 0.97 / 0.97 | 0.969 | 0.291 | 0.982 |
| bixverse v1 | 0.32 | 2.80 | 2.55 | 0.75 / 0.71 | 0.966 | 0.256 | 1.005 |
| harmonypy 2.1.0 | 0.45 | 4.32 | **1.41** | 1 / 1 | 0.968 | 0.282 | 0.982 |

Inside the pipeline (Docker) bixverse's `harmony_v2_sc` takes 0.5 s at 100k,
1.7 s at 500k and 3.0 s at 1M; the gap to the standalone numbers is the R
wrapper plus the VM, not split further. harmonypy 2.0.2 took 9.1, 45 and 88 s for the same Scanpy step.

### What it shows

- **bixverse is about 6x faster than scrapper end to end, at a quarter of the
  memory.** From h5ad without tSNE: 17 s against 100 s at 100k, 87 s against
  533 s at 500k. Scanpy on Dask comes closest (79, 320 and 727 s, but without
  DGE); bixverse takes 209 s for 1M cells.
- **At 1M only the out-of-core designs survive.** bixverse, Scanpy Dask and
  Seurat BPCells. scrapper makes 500k at the memory ceiling with 2.6 GB swap;
  Seurat standard OOMs in PCA at 500k, Seurat 5.6.0 included.
- **Embeddings: bixverse and Seurat lead, Scanpy trails.** Harmony purity
  0.969 to 0.971 for both at every size, scrapper 0.927, Scanpy 0.889 to
  0.908. UMAP and tSNE keep the same order.
- **Clustering: scrapper wins the native ARI.** 0.94 at every size with 9
  clusters for 12 groups, from its rank-weighted sNN without pruning. bixverse
  and Seurat prune a Jaccard sNN and over-split (ARI 0.70 to 0.87; 13 to 44
  clusters on the CPU, up to 90 on the GPU); their NMI stays at 0.88 to 0.92.
- **The rare group goes to Seurat and bixverse.** Rare F1 0.24 to 0.35 for
  both, against 0.09 to 0.14 for Scanpy and scrapper. Harmony halves rare
  purity everywhere, as the group sits in a quarter of the batches.
- **DGE: bixverse ranks like presto, in a fraction of the time.** 0.5 to 3.4 s
  against 4 to 23 s for scrapper, 47 to 450 s for Scanpy and 88 to 800 s for
  BPCells. On the shared genes at 100k bixverse and Seurat agree to the last
  digit (R-precision 0.975); scrapper and Scanpy rank detectable markers slightly
  better (0.93 to 0.94 against 0.89 to 0.90). BPCells drops to 0.69 and 0.63
  at 500k and 1M; why is not checked.
- **tSNE: bixverse is 2x to 5x faster in every category.** Standard
  Barnes-Hut at 500k: 4.3 min against 22 min for Scanpy and 23 min for BPCells,
  both of which time out at 1M. Quick-and-dirty: 41 s against scrapper's
  153 s at 500k.
- **Disk is bixverse's cost.** Its two on-disk views take 1.3, 6.6 and
  13.2 GB, about 3.6x BPCells (0.4, 1.8, 3.7 GB) and 1.6x the 8.1 GB h5ad it
  reads at 1M.
- **Harmony: bixverse v2 is 2x faster than harmonypy 2.1.0 on the same input,
  with the same answer.** 97% shared neighbours and identical purity and batch
  mixing; harmonypy needs 1.1 GB less at 1M. v1 gives a different embedding
  (71% to 75% overlap, lower rare purity).

## PBMC

Older stack: bixverse 0.5.5, Seurat 5.5.1, harmonypy 2.0.2, manifoldsR 0.3.6,
no DGE step (TODO: rerun on the released versions). bixverse had no
quick-and-dirty tSNE then; scrapper's default tSNE is that row.

![Scaling: time and peak memory against cells](figures/scaling.png)

![Wall time per step for every framework and size](figures/steps_heatmap.png)

### 100k cells (69,412 after QC)

| step | bixverse mtx | bixverse h5ad | bixverse GPU* | Scanpy mtx | Scanpy h5ad | Scanpy dask | scrapper mtx | scrapper h5ad | Seurat std mtx | Seurat std h5ad | Seurat BPCells | OSCA HDF5 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| load | 11.1 | 6.9 | 6.1 | 21.4 | 3.3 | 5.9 | 42.5 | 6.3 | 43.6 | 9.9 | 14.4 | 38.2 |
| qc | 1.0 | 1.1 | 0.7 | 0.8 | 0.8 | 1.0 | 0.5 | 0.4 | 2.8 | 2.6 | 1.2 | 10.0 |
| normalise | n/a | n/a | n/a | 2.0 | 2.1 | 0.0 | 0.1 | 0.1 | 4.9 | 4.7 | 2.0 | 8.0 |
| hvg | 0.4 | 0.5 | 0.3 | 1.3 | 1.4 | 1.7 | 0.2 | 0.2 | 7.3 | 6.8 | 2.6 | 609.2 |
| pca | 1.5 | 1.5 | 0.5 | 1.4 | 1.5 | 3.9 | 1.8 | 1.6 | 24.5 | 24.0 | 73.4 | 63.4 |
| harmony | 4.9 | 4.9 | 2.1 | 8.7 | 8.5 | 8.5 | 11.1 | 12.1 | 13.4 | 13.0 | 13.6 | 13.9 |
| knn_snn | 1.7 | 1.7 | 0.9 | 28.3 | 29.6 | 23.6 | 4.6 | 4.3 | 13.5 | 13.0 | 14.1 | 28.5 |
| cluster | 1.4 | 1.4 | 1.0 | 1.9 | 2.1 | 2.0 | 8.6 | 8.1 | 17.2 | 16.3 | 18.4 | 7.8 |
| umap | 2.5 | 2.5 | 0.6 | 27.3 | 26.7 | 26.9 | 32.8 | 32.3 | 58.1 | 54.2 | 56.2 | 27.8 |
| tsne_default | 26.1 | 25.9 | 23.9 | 102.9 | 103.1 | 99.5 | n/a | n/a | 74.4 | 70.9 | 73.9 | 98.9 |
| tsne_fft | 8.5 | 8.2 | 4.4 | 32.3 | 31.7 | 30.7 | n/a | n/a | 25.8 | 24.0 | 23.9 | n/a |
| tsne_quick (qd) | - | - | - | n/a | n/a | n/a | 18.2 | 16.5 | n/a | n/a | n/a | n/a |
| **total** | **59** | **55** | **40** | **228** | **211** | **204** | **120** | **82** | **286** | **239** | **294** | **906** |
| total without tSNE | 25 | 20 | 12 | 93 | 76 | 74 | 102 | 65 | 185 | 144 | 196 | 807 |
| **peak GB** | **1.6** | **1.7** | **4.2** | **6.8** | **2.6** | **1.9** | **5.3** | **4.8** | **8.7** | **8.7** | **1.9** | **22.7** |
| peak swap GB | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 3.7 |

### 500k cells (346,259 after QC)

| step | bixverse mtx | bixverse h5ad | bixverse GPU* | Scanpy mtx | Scanpy h5ad | Scanpy dask | scrapper mtx | scrapper h5ad | Seurat std mtx | Seurat std h5ad | Seurat BPCells | OSCA HDF5 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| load | 73.2 | 30.6 | 31.2 | **OOM** | 19.0 | 23.3 | **OOM** | 150.3 | **OOM** | **OOM** | 71.6 | 159.5 |
| qc | 2.8 | 3.3 | 2.2 | - | 3.8 | 4.2 | - | 2.1 | - | - | 4.7 | 47.2 |
| normalise | n/a | n/a | n/a | - | 3.5 | 0.0 | - | 0.4 | - | - | 8.3 | 29.3 |
| hvg | 1.0 | 1.1 | 0.9 | - | 3.1 | 5.0 | - | 0.9 | - | - | 8.8 | **OOM (worker)** |
| pca | 3.5 | 3.5 | 2.0 | - | 5.7 | 10.3 | - | 10.2 | - | - | 358.0 | - |
| harmony | 31.1 | 33.2 | 6.9 | - | 58.3 | 58.4 | - | 95.6 | - | - | 92.0 | - |
| knn_snn | 8.8 | 9.3 | 4.2 | - | 32.3 | 27.7 | - | 26.2 | - | - | 94.1 | - |
| cluster | 7.8 | 7.9 | 5.9 | - | 13.4 | 12.9 | - | 83.2 | - | - | 113.3 | - |
| umap | 21.3 | 21.5 | 2.7 | - | 158.0 | 152.4 | - | 149.8 | - | - | 340.0 | - |
| tsne_default | 156.0 | 153.6 | 134.2 | - | 840.4 | 813.0 | n/a | n/a | - | - | 639.4 | - |
| tsne_fft | 39.9 | 40.3 | 18.7 | - | 114.9 | 110.1 | n/a | n/a | - | - | 108.4 | n/a |
| tsne_quick (qd) | - | - | - | n/a | n/a | n/a | - | 98.3 | n/a | n/a | n/a | n/a |
| **total** | **345** | **304** | **209** | failed | **1252** | **1217** | failed | **617** | failed | failed | **1838** | failed |
| total without tSNE | 150 | 110 | 56 | failed | 297 | 294 | failed | 519 | failed | failed | 1091 | failed |
| **peak GB** | **6.3** | **6.5** | **10.0** | **22.3** | **14.2** | **6.8** | **22.7** | **22.7** | **22.7** | **22.8** | **5.5** | **22.7** |
| peak swap GB | 0.0 | 0.0 | 0.0 | 3.9 | 0.0 | 0.0 | 3.8 | 3.2 | 3.7 | 3.5 | 0.0 | 3.7 |

bixverse CPU tSNE builds its kNN with IVF at this size (kmknn at 100k);
kmknn runs are in `results/archive_tsne_kmknn`.

### Full data set (684,932 after QC)

| step | bixverse mtx | bixverse h5ad | bixverse GPU* | Scanpy mtx | Scanpy h5ad | Scanpy dask | scrapper mtx | scrapper h5ad | Seurat std mtx | Seurat std h5ad | Seurat BPCells | OSCA HDF5 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| load | 148.2 | 77.9 | 74.0 | **OOM** | **OOM** | 42.3 | **OOM** | **OOM** | **OOM** | **OOM** | 142.7 | 315.6 |
| qc | 4.5 | 4.9 | 2.9 | - | - | 7.4 | - | - | - | - | 9.5 | 101.4 |
| normalise | n/a | n/a | n/a | - | - | 0.0 | - | - | - | - | 16.5 | 61.0 |
| hvg | 1.8 | 1.8 | 1.8 | - | - | 9.0 | - | - | - | - | 16.1 | **OOM (worker)** |
| pca | 6.3 | 6.2 | 5.6 | - | - | 17.2 | - | - | - | - | 702.3 | - |
| harmony | 64.9 | 62.9 | 16.4 | - | - | 137.8 | - | - | - | - | 213.1 | - |
| knn_snn | 17.5 | 17.8 | 8.3 | - | - | 33.1 | - | - | - | - | 201.0 | - |
| cluster | 15.6 | 15.7 | 11.7 | - | - | 29.9 | - | - | - | - | 249.6 | - |
| umap | 47.9 | 50.9 | 6.0 | - | - | 352.1 | - | - | - | - | 759.5 | - |
| tsne_default | 372.8 | 371.3 | 324.6 | - | - | 1955.3 | n/a | n/a | - | - | 1645.1 | - |
| tsne_fft | 120.7 | 124.7 | 39.5 | - | - | 258.4 | n/a | n/a | - | - | 228.9 | n/a |
| **total** | **800** | **734** | **491** | failed | failed | **2843** | failed | failed | failed | failed | **4184** | failed |
| total without tSNE | 307 | 238 | 127 | failed | failed | 629 | failed | failed | failed | failed | 2310 | failed |
| **peak GB** | **9.8** | **8.9** | **15.6** | **22.5** | **22.5** | **9.5** | **22.8** | **22.8** | **22.8** | **22.8** | **9.7** | **22.8** |
| peak swap GB | 0.0 | 0.1 | 0.0 | 3.7 | 3.2 | 0.0 | 3.5 | 3.0 | 3.4 | 3.0 | 0.0 | 3.6 |

bixverse CPU tSNE builds its kNN with IVF at this size (kmknn at 100k);
kmknn runs are in `results/archive_tsne_kmknn`.

### Warm start

Reconnecting to data a cold run already converted (`WARM=1 scripts/run.sh`),
load step only. bixverse reopens its two views and the stored cell map, so its
object holds the post-QC cells; BPCells reopens the pre-filtered, pre-QC matrix
and builds the Seurat object. Each warm run goes straight after its cold run,
so the files are likely still in the page cache. Warm peak GB is the load only;
cold load s is the load step of the full cold run.

![Cold against warm load for bixverse and Seurat + BPCells](figures/warm_start.png)

| size | framework | cold load s | warm load s | warm peak GB |
|---|---|---|---|---|
| 100k | bixverse | 11.1 | 0.3 | 0.2 |
| 100k | Seurat BPCells | 14.4 | 2.3 | 0.8 |
| 500k | bixverse | 73.2 | 0.6 | 0.3 |
| 500k | Seurat BPCells | 71.6 | 10.4 | 0.9 |
| full | bixverse | 148.2 | 2.3 | 0.5 |
| full | Seurat BPCells | 142.7 | 20.8 | 1.1 |

### What it shows

![Speed-up per step against in-memory Scanpy at 500k](figures/speedup_vs_scanpy_500k.png)

![Speed-up per step against Scanpy with Dask on the full data set](figures/speedup_vs_scanpy_dask_full.png)

- **Three frameworks finish the full data set, all out-of-core.** Without
  tSNE: bixverse 4.0 min from h5ad (5.1 min from mtx, 2.1 min on the GPU),
  Scanpy Dask 10.5 min, Seurat + BPCells 38.5 min. Everything that holds the
  counts in memory dies at load, and OSCA's HDF5 path dies in HVG.
- **Memory is now a tie among the survivors.** Full data peaks: bixverse 8.9
  GB (h5ad) and 9.8 GB (mtx), Scanpy Dask 9.5 GB, Seurat + BPCells 9.7 GB.
- **Each out-of-core design pays somewhere else.** bixverse pays up front to
  convert into its two views (78 s from h5ad on the full data) and is fast
  after. Dask loads in 42 s but re-reads the file on every forced pass, and
  its UMAP (352 s) and Harmony (138 s) are the stock in-memory ones. BPCells
  re-evaluates its lazy chain on every pass (PCA 702 s, UMAP 760 s).
- **Against baseline in-memory Scanpy** at 500k, the largest size it survives:
  bixverse from h5ad is 2.7x faster without tSNE (110 s against 297 s) at under
  half the memory (6.5 GB against 14.2 GB). Scanpy only wins the load.
- **scrapper is fast wherever it stays in C++.** Best QC, HVG and quick tSNE
  at 100k, but the loaders, the R harmony package and a UMAP that rebuilds the
  kNN cost it, and the in-memory path runs out of room at 500k from mtx.
- **A warm start removes the conversion cost.** On the full data bixverse
  reconnects in 2.3 s at 0.5 GB (148 s cold from mtx, 78 s from h5ad), and
  Seurat + BPCells in 20.8 s at 1.1 GB (143 s cold). At 500k: 0.6 s against
  10.4 s. So the up-front conversion bixverse pays is a one-off per data set:
  the load was 78 s of its 238 s without tSNE from h5ad. BPCells' warm load
  grows with the data (2.3, 10.4, 20.8 s); where that time goes is not timed.
  The BPCells PCA and UMAP cost above is untouched by a warm start.
- **Exact kNN inside tSNE does not scale.** kmknn took 49 s of the 78 s
  `tsne_fft` at 500k and 182 s of 258 s on the full data. IVF cuts that to 12 s
  and 45 s, and `tsne_fft` to 40 s and 121 s (mtx). IVF recall against kmknn
  is not measured here.
- **The GPU earns its keep from 500k.** 56 s without tSNE at 500k and 127 s on
  the full data. tSNE is now most of every run that has it (three-kernel FFT on the GPU: 19
  s at 500k, 40 s on the full data, against 40 s and 121 s for `fft_3k` on the CPU
  with an IVF kNN), so dropping it from a large-data workflow
  is the smart call.
