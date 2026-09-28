# single-cell-benchmark

How far do the big single cell frameworks get on a MacBook Air class machine?
The 1M cell Parse Biosciences PBMC data set, the same ten step workflow in
every framework, 24 GB of RAM and 8 cores. Wall time and peak memory per step.

## Setup

- **Data**: Parse 1M PBMC (987,585 cells, 60,664 genes, 24 samples), plus
  random 100k and 500k cell subsamples (`scripts/subsample.py`, seed 42). Every
  framework reads the same mtx; the h5ad files come from `scripts/to_h5ad.py`.
- **Machine**: M1 Max, Docker Desktop, containers capped at `--cpus=8
  --memory=24g`. The VM itself has ~23.4 GB plus ~4 GB swap, and that is the
  limit that actually bites. Slightly stricter than an Air.
- **GPU**: Docker has no Metal access, so the bixverse.gpu row runs natively on
  macOS (`scripts/run_native.sh`). No memory cap there, and its peak is process
  RSS including resident memory-mapped files. Not comparable to the cgroup
  numbers.
- **Memory**: cgroup `anon` sampled once a second (`docker/monitor.sh`). Page
  cache is excluded, so streaming tools are not charged for their files.
- **Repeats**: one per run. Treat differences of a few seconds as noise.
- **bixverse builds**: `scripts/vendor.sh` exports `main` of the local checkouts
  ahead of r-universe. The full data set still shows bixverse 0.5.2 (marked in
  the column headers) until it is rerun; 0.5.2 results for all sizes live in
  `results/archive_bixverse_0.5.2/`.

| framework | version |
|---|---|
| bixverse | 0.5.3 (bixverse.gpu 0.3.3, manifoldsR 0.3.4), built from `main`: bixverse 888cc02, bixverse.gpu 5d35214, manifoldsR 5a30cd1 |
| Scanpy | 1.12.4 (harmonypy 2.0.2, openTSNE 1.0.4, scikit-learn 1.9.1) |
| scrapper | 1.6.3 |
| Seurat | 5.5.1 (BPCells 0.3.1, harmony 2.0.5) |

## Workflow

Same steps and parameters everywhere, each via the framework's own documented
path.

1. **load**: pre-filter as bixverse does it. Genes in at least 5 cells first,
   then cells with at least 100 genes and 250 UMIs. bixverse fuses the
   log-normalisation into this streaming pass, so it has no separate
   normalise step.
2. **qc**: MT < 5%, total UMIs >= 750, detected genes >= 250.
3. **normalise**: library size to 1e4, log1p.
4. **hvg**: 2000 genes, each framework's default method.
5. **pca**: 30 components. Scanpy and scrapper centre only; Seurat and bixverse
   also scale to unit variance.
6. **harmony**: by sample.
7. **knn_snn**: k = 15.
8. **cluster**: Leiden, resolution 1. The graphs differ, so the cluster counts
   do not compare.
9. **umap**: defaults.
10. **tsne**: perplexity 30. `tsne_default` is each framework's default
    Barnes-Hut; `tsne_fft` is FFT where it exists (bixverse, Seurat's FIt-SNE,
    openTSNE for Scanpy). scrapper's qdtsne defaults to theta = 1 and 500
    iterations, so `tsne_matched` reruns it at theta = 0.5, 1000 iterations and
    250 early exaggeration rounds, like everyone else.

bixverse uses nndescent for the sNN kNN and kmknn inside tSNE. Every tSNE
builds its own kNN at k = 3 x perplexity. For UMAP, bixverse and Scanpy reuse
the graph; Seurat and scrapper rebuild it.

## Results

Seconds per step. **OOM** marks the step where the container was killed.

### 100k cells (69,412 after QC)

| step | bixverse mtx | bixverse h5ad | bixverse GPU (native) | Scanpy mtx | Scanpy h5ad | scrapper mtx | scrapper h5ad | Seurat std mtx | Seurat std h5ad | Seurat BPCells |
|---|---|---|---|---|---|---|---|---|---|---|
| load | 20.0 | 13.9 | 18.8 | 21.4 | 3.3 | 42.5 | 6.3 | 43.6 | 9.9 | 15.1 |
| qc | 0.8 | 1.0 | 0.7 | 0.8 | 0.8 | 0.5 | 0.4 | 2.8 | 2.6 | 1.2 |
| normalise | n/a | n/a | n/a | 2.0 | 2.1 | 0.1 | 0.1 | 4.9 | 4.7 | 2.2 |
| hvg | 0.4 | 0.5 | 0.4 | 1.3 | 1.4 | 0.2 | 0.2 | 7.3 | 6.8 | 2.7 |
| pca | 1.5 | 1.4 | 0.7 | 1.4 | 1.5 | 1.8 | 1.6 | 24.5 | 24.0 | 75.3 |
| harmony | 4.8 | 4.9 | 2.5 | 8.7 | 8.5 | 11.1 | 12.1 | 13.4 | 13.0 | 14.2 |
| knn_snn | 1.7 | 1.8 | 2.0 | 28.3 | 29.6 | 4.6 | 4.3 | 13.5 | 13.0 | 13.8 |
| cluster | 1.3 | 1.3 | 1.1 | 1.9 | 2.1 | 8.6 | 8.1 | 17.2 | 16.3 | 18.1 |
| umap | 2.7 | 2.6 | 0.6 | 27.3 | 26.7 | 32.8 | 32.3 | 58.1 | 54.2 | 57.5 |
| tsne_default | 25.8 | 25.8 | 24.4 | 102.9 | 103.1 | 18.2 | 16.5 | 74.4 | 70.9 | 77.9 |
| tsne_matched | n/a | n/a | n/a | n/a | n/a | 41.5 | 36.9 | n/a | n/a | n/a |
| tsne_fft | 9.9 | 10.1 | 7.7 | 32.3 | 31.7 | n/a | n/a | 25.8 | 24.0 | 25.7 |
| **total** | **69** | **63** | **59** | **228** | **211** | **162** | **119** | **286** | **239** | **304** |
| total without tSNE | 33 | 27 | 27 | 93 | 76 | 102 | 65 | 185 | 144 | 200 |
| **peak GB** | **1.5** | **1.5** | **4.1** | **6.8** | **2.6** | **5.3** | **4.8** | **8.7** | **8.7** | **1.7** |
| peak swap GB | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |

### 500k cells (346,259 after QC)

| step | bixverse mtx | bixverse h5ad | bixverse GPU (native) | Scanpy mtx | Scanpy h5ad | scrapper mtx | scrapper h5ad | Seurat std mtx | Seurat std h5ad | Seurat BPCells |
|---|---|---|---|---|---|---|---|---|---|---|
| load | 111.8 | 71.9 | 87.9 | **OOM** | 19.0 | **OOM** | 150.3 | **OOM** | **OOM** | 74.7 |
| qc | 2.6 | 2.6 | 2.2 | - | 3.8 | - | 2.1 | - | - | 4.8 |
| normalise | n/a | n/a | n/a | - | 3.5 | - | 0.4 | - | - | 8.3 |
| hvg | 1.0 | 1.2 | 1.1 | - | 3.1 | - | 0.9 | - | - | 9.3 |
| pca | 3.5 | 3.5 | 2.6 | - | 5.7 | - | 10.2 | - | - | 357.4 |
| harmony | 30.4 | 33.0 | 6.9 | - | 58.3 | - | 95.6 | - | - | 91.8 |
| knn_snn | 8.5 | 9.2 | 9.0 | - | 32.3 | - | 26.2 | - | - | 89.6 |
| cluster | 7.4 | 7.6 | 5.6 | - | 13.4 | - | 83.2 | - | - | 111.2 |
| umap | 21.8 | 22.7 | 2.6 | - | 158.0 | - | 149.8 | - | - | 344.4 |
| tsne_default | 189.3 | 189.4 | 135.7 | - | 840.4 | - | 98.3 | - | - | 628.7 |
| tsne_matched | n/a | n/a | n/a | n/a | n/a | - | 202.2 | n/a | n/a | n/a |
| tsne_fft | 88.7 | 90.1 | 34.9 | - | 114.9 | n/a | n/a | - | - | 109.5 |
| **total** | **465** | **431** | **289** | failed | **1252** | failed | **819** | failed | failed | **1830** |
| total without tSNE | 187 | 152 | 118 | failed | 297 | failed | 519 | failed | failed | 1092 |
| **peak GB** | **6.4** | **7.5** | **11.5** | **22.3** | **14.2** | **22.7** | **22.7** | **22.7** | **22.8** | **5.3** |
| peak swap GB | 0.0 | 0.0 | 0.0 | 3.9 | 0.0 | 3.8 | 3.2 | 3.7 | 3.5 | 0.0 |

### Full data set (684,932 after QC)

| step | bixverse mtx (0.5.2) | bixverse h5ad (0.5.2) | bixverse GPU (native) (0.5.2) | Scanpy mtx | Scanpy h5ad | scrapper mtx | scrapper h5ad | Seurat std mtx | Seurat std h5ad | Seurat BPCells |
|---|---|---|---|---|---|---|---|---|---|---|
| load | 222.3 | 160.0 | 159.4 | **OOM** | **OOM** | **OOM** | **OOM** | **OOM** | **OOM** | 139.7 |
| qc | 3.3 | 3.8 | 3.7 | - | - | - | - | - | - | 9.2 |
| normalise | n/a | n/a | n/a | - | - | - | - | - | - | 15.9 |
| hvg | 1.9 | 1.8 | 2.9 | - | - | - | - | - | - | 15.8 |
| pca | 18.7 | 18.8 | 6.7 | - | - | - | - | - | - | 703.0 |
| harmony | 63.7 | 69.4 | 13.3 | - | - | - | - | - | - | 220.1 |
| knn_snn | 17.7 | 18.8 | 18.0 | - | - | - | - | - | - | 201.3 |
| cluster | 15.1 | 15.6 | 8.5 | - | - | - | - | - | - | 248.7 |
| umap | 51.0 | 53.4 | 5.7 | - | - | - | - | - | - | 749.4 |
| tsne_default | 531.3 | 558.1 | 808.3 | - | - | - | - | - | - | 1600.3 |
| tsne_fft | 313.8 | 326.5 | 599.1 | - | - | n/a | n/a | - | - | 227.4 |
| **total** | **1239** | **1226** | **1626** | failed | failed | failed | failed | failed | failed | **4131** |
| total without tSNE | 394 | 342 | 218 | failed | failed | failed | failed | failed | failed | 2303 |
| **peak GB** | **11.0** | **17.5** | **18.2** | **22.5** | **22.5** | **22.8** | **22.8** | **22.8** | **22.8** | **9.4** |
| peak swap GB | 0.0 | 0.1 | 0.0 | 3.7 | 3.2 | 3.5 | 3.0 | 3.4 | 3.0 | 0.0 |

## What it shows

- **Only bixverse and Seurat + BPCells finish the full data set.** bixverse
  0.5.2 takes 6.6 min without tSNE (5.7 min from h5ad), Seurat + BPCells 38
  min. Everything that holds the counts in memory dies at load.
- **The loaders decide who survives.** Every OOM happens in load. Reading the
  mtx kills Scanpy, scrapper and Seurat at 500k already. From h5ad, Scanpy and
  scrapper make it through 500k, scrapper only just (22.7 GB plus 3.2 GB swap).
- **BPCells buys memory with time.** Lowest peak at every size, but lazy
  scaling makes PCA the slowest by far (703 s on the full data).
- **scrapper is fast wherever it stays in C++.** QC and HVG beat everything at
  100k. It loses time in R's loaders, the R harmony package and a UMAP that
  rebuilds the kNN. With matched settings its tSNE is level with bixverse's
  Barnes-Hut at 500k.
- **bixverse PCA is no longer the weak spot.** 3.5 s at 500k against 5.7 s for
  Scanpy and 10.2 s for scrapper, while reading from disk and scaling to unit
  variance.
- **The GPU earns its keep from 500k.** 118 s without tSNE at 500k (152 s on
  CPU from h5ad), and FFT tSNE in 34.9 s against 88.7 s on CPU, 109.5 s for
  FIt-SNE and 114.9 s for openTSNE. tSNE still dominates every run that has it,
  so dropping it from a large-data workflow is the smart call.

## bixverse: 0.5.2 against 0.5.3

Seconds at 500k (346,259 cells after QC).

| step | mtx 0.5.2 | mtx 0.5.3 | h5ad 0.5.2 | h5ad 0.5.3 | GPU 0.5.3 |
|---|---|---|---|---|---|
| load | 100.4 | 111.8 | 67.6 | 71.9 | 87.9 |
| pca | 14.0 | 3.5 | 13.0 | 3.5 | 2.6 |
| harmony | 32.8 | 30.4 | 33.0 | 33.0 | 6.9 |
| umap | 22.6 | 21.8 | 23.4 | 22.7 | 2.6 |
| tsne_default | 204.7 | 189.3 | 197.1 | 189.4 | 135.7 |
| tsne_fft | 103.5 | 88.7 | 101.1 | 90.1 | 34.9 |
| total | 498 | 465 | 456 | 431 | 289 |
| without tSNE | 190 | 187 | 157 | 152 | 118 |
| peak GB | 8.4 | 6.4 | 8.3 | 7.5 | 11.5* |
| clusters | 517 | 44 | 510 | 44 | 60 |

\* native macOS RSS, not comparable to the Docker numbers.

- **sNN pruning**: fixed. 517 clusters down to 44 at 500k. At 100k, clusters
  under 10 cells went from 27 to 1. Scanpy, scrapper and Seurat still land on
  15 to 24, so bixverse splits finer at resolution 1, but that is graph
  weighting now, not debris.
- **PCA**: 4x faster at 500k, 2x at 100k.
- **GPU tSNE**: new defaults. FFT went from 41.1 s to 7.7 s at 100k.
- **Still open**: `get_h5ad_dimensions()` takes the gene count from the first
  plain dataset in `/var`, and h5ad files written with pandas >= 3 have none
  (`scripts/to_h5ad.py` pins pandas < 3 as a workaround). The h5ad load peaked
  at 17.5 GB on the full data under 0.5.2. The full data set needs a rerun on
  0.5.3.

## Running it

```bash
uv run scripts/subsample.py ~/Desktop/parse_pbmc_1m data/parse_100k 100000
uv run scripts/to_h5ad.py data/parse_100k
docker build -f docker/r.Dockerfile -t scbench-r .
docker build -f docker/py.Dockerfile -t scbench-py .

# tool: bixverse | scanpy | scrapper | seurat_standard | seurat_bpcells
[INPUT=h5ad] [BIX_KNN=nndescent] [TAG=suffix] scripts/run.sh <tool> parse_100k
scripts/run_native.sh parse_100k       # bixverse.gpu on Metal

uv run scripts/tables.py results
```
