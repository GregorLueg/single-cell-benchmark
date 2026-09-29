# single-cell-benchmark

How far do the big single cell frameworks get on a MacBook Air class machine?
The 1M cell Parse Biosciences PBMC data set, the same ten step workflow in
every framework, 24 GB of RAM and 8 cores. Wall time and peak memory per step.

## Setup

- **Data**: Parse 1M PBMC (987,585 cells, 60,664 genes, 24 samples), plus
  random 100k and 500k cell subsamples (`scripts/subsample.py`, seed 42). The
  mtx rows read the Parse mtx; the h5ad rows read `scripts/to_h5ad.py` output.
- **Machine**: M1 Max, Docker Desktop, containers capped at
  `--cpus=8 --memory=24g`. The VM itself has ~23.4 GB plus ~4 GB swap, and that
  is the limit that actually bites. Slightly stricter than an Air.
- **GPU**: Docker has no Metal access, so the bixverse GPU row runs natively on
  macOS (`scripts/run_native.sh`). No memory cap there, and its peak is process
  RSS including resident memory-mapped files. Not comparable to the Docker
  numbers, and its disk I/O skips the VM, so its load is faster too.
- **Memory**: cgroup `anon` sampled once a second (`docker/monitor.sh`). Page
  cache is excluded, so streaming tools are not charged for their files.
- **Repeats**: one per run. Treat differences of a few seconds as noise.
- **bixverse**: built from the local checkouts (`scripts/vendor.sh`) ahead of
  r-universe; loaders use `csc_mem_gb = 8` as in the big data vignette. The GPU
  row uses GPU NNDescent (`find_neighbours_gpu_sc`) for the kNN. Results for
  0.5.2 and 0.5.3 live in `results/archive_bixverse_*`.
- **Scanpy Dask**: X read lazily from the h5ad in 50k cell CSR chunks, threaded
  scheduler. `sc.pp.calculate_qc_metrics` peaks at 16.6 GB transiently on 500k
  cells under Dask, whatever the chunk size, and kills the full data set. The
  Dask row therefore computes the three per-cell QC sums with `map_blocks`
  instead (6.2 GB peak, same cells kept). Everything else is stock Scanpy.
- **OSCA HDF5**: SingleCellExperiment over `HDF5Array::H5ADMatrix`, the
  documented Bioconductor path with `MulticoreParam(8)` (pipeline as of
  commit f124aa9). It does not survive HVG at 500k; see the caveats for what
  was tried.

| framework | version |
|---|---|
| bixverse | 0.5.4 (`feat-better-sc-io` 87f73fa, bixverse-rs `release-0.5.6` cb90e16), bixverse.gpu 0.3.3 (`main` 5d35214), manifoldsR 0.3.4 (`main` 5a30cd1) |
| Scanpy | 1.12.4 (anndata 0.13.4, dask 2026.8.0, harmonypy 2.0.2, openTSNE 1.0.4, scikit-learn 1.9.1) |
| scrapper | 1.6.3 |
| Seurat | 5.5.1 (BPCells 0.3.1, harmony 2.0.5) |
| OSCA | scran 1.40.0, scater 1.40.2, scuttle 1.22.0, HDF5Array 1.40.0, BiocSingular 1.28.0, bluster 1.22.0 |

## Workflow

Same steps and parameters everywhere, each via the framework's own documented
path.

1. **load**: pre-filter as bixverse does it. Genes in at least 5 cells first,
   then cells with at least 100 genes and 250 UMIs. bixverse fuses the
   log-normalisation into this streaming pass, so it has no separate
   normalise step.
2. **qc**: MT < 5%, total UMIs >= 750, detected genes >= 250.
3. **normalise**: library size to 1e4 and log1p (bixverse, Scanpy, Seurat);
   centred size factors and log2 (scrapper, OSCA defaults).
4. **hvg**: 2000 genes, each framework's default method.
5. **pca**: 30 components. Scanpy, scrapper and OSCA centre only; Seurat and
   bixverse also scale to unit variance.
6. **harmony**: by sample.
7. **knn_snn**: k = 15.
8. **cluster**: Leiden, resolution 1. The graphs differ, so the cluster counts
   do not compare: Scanpy clusters the UMAP fuzzy graph, Seurat and bixverse a
   Jaccard sNN with pruning, scrapper and OSCA a rank-weighted sNN.
9. **umap**: defaults.
10. **tsne**: perplexity 30. `tsne_default` is each framework's default
    Barnes-Hut; `tsne_fft` is FFT where it exists (bixverse, Seurat's FIt-SNE,
    openTSNE for Scanpy). scrapper's qdtsne defaults to theta = 1 and 500
    iterations, so `tsne_matched` reruns it at theta = 0.5, 1000 iterations and
    250 early exaggeration rounds, like everyone else.

bixverse uses nndescent for the sNN kNN and kmknn inside tSNE. Every tSNE
builds its own kNN at k = 3 x perplexity. For UMAP, bixverse and Scanpy reuse
the graph; Seurat, scrapper and OSCA rebuild it.

## Results

Seconds per step. **OOM** marks the step where the container was killed;
**OOM (worker)** where a forked BiocParallel worker was.

### 100k cells (69,412 after QC)

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

### 500k cells (346,259 after QC)

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

### Full data set (684,932 after QC)

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

## bixverse across versions

Seconds without tSNE / peak GB / clusters at resolution 1. The GPU peak is
native RSS.

| size | variant | 0.5.2 | 0.5.3 | 0.5.4 |
|---|---|---|---|---|
| 100k | mtx | 34 / 2.2 / 57 | 33 / 1.5 / 32 | 24 / 1.6 / 32 |
| 100k | h5ad | 29 / 2.1 / 54 | 27 / 1.5 / 32 | 21 / 1.6 / 32 |
| 100k | GPU | 23 / 4.3 / 40 | 27 / 4.1 / 32 | 13 / 4.3 / 33 |
| 500k | mtx | 190 / 8.4 / 517 | 187 / 6.4 / 44 | 149 / 6.3 / 43 |
| 500k | h5ad | 157 / 8.3 / 510 | 152 / 7.5 / 44 | 111 / 6.5 / 43 |
| 500k | GPU | - | 118 / 11.5 / 60 | 62 / 10.0 / 59 |
| full | mtx | 394 / 11.0 / 1,684 | 392 / 10.8 / 55 | 280 / 10.6 / 52 |
| full | h5ad | 342 / 17.5 / 1,682 | 327 / 17.2 / 53 | 233 / 9.0 / 53 |
| full | GPU | 218 / 18.2 / 2,804 | 249 / 16.8 / 92 | 124 / 16.1 / 91 |

- **0.5.3**: sNN pruning no longer fragments the graph (1,684 clusters down to
  55 on the full data); PCA 3x to 4x faster; GPU tSNE defaults reworked.
- **0.5.4**: streaming h5ad ingest and a memory-capped CSR to CSC conversion
  (`csc_mem_gb`). Full data load from h5ad 158 s to 71 s, peak 17.2 GB to 9.0
  GB; from mtx 232 s to 112 s. The GPU row also switched to GPU NNDescent for
  the kNN (9.0 s to 4.0 s at 500k).

## Caveats

- **One repeat, one machine.** Apple Silicon under Docker, not a real 24 GB
  laptop.
- **No quality metrics yet.** Timings only; embeddings, integration and
  clustering quality are not scored.
- **Harness code.** The R pre-filter for scrapper and Seurat standard makes
  copies (`counts > 0`, column subsetting); part of their in-memory OOMs may
  be ours. The Scanpy Dask QC is hand-written (see Setup).
- **OSCA: OOMs in parallel, impractical serially.** The documented path
  (`MulticoreParam(8)`) takes 609 s for HVG at 100k at 22.7 GB plus 3.7 GB
  swap; at 500k and on the full data the kernel kills a forked worker there.
  Two follow-ups at 100k, on a machine shared with other tests:
  - `beachmat.hdf5` gives the C++ layer native access to the h5ad seed
    (without it beachmat logs "unknown matrix fallback for
    'CSC_H5ADMatrixSeed'"). QC halves, 10.0 s to 4.9 s, but HVG still climbs
    to ~18 GB plus swap.
  - Serial HVG (`SerialParam`) holds ~3 to 4 GB with no swap, but had not
    finished after 27 min, and was stopped. Linear extrapolation puts 500k at
    hours.
  The memory comes from 8 workers splitting genes over a cell-major file; the
  time from per-gene access to cell-contiguous storage. A gene-major HDF5 copy
  or a single pass of per-gene accumulators would probably fix both; neither is
  tried here. On a machine with more memory, more HVG workers may fit. The same
  logs mark `perCellQCMetrics`, `librarySizeFactors` and `normalizeCounts`
  as deprecated in favour of scrapper.
- **Defaults differ** in scaling, normalisation and graph construction; see
  Workflow.

## Open items

- bixverse: the CSR to CSC transpose is still the largest part of a cold load.
- bixverse GPU: FFT tSNE on the device (manifolds-rs `fft_3k_gpu`) is not wired
  in yet.
- `scripts/to_h5ad.py` pins pandas < 3 because bixverse 0.5.3 could not read
  the gene count from `/var` without a plain dataset; recheck with 0.5.4.
- Warm start (reconnecting to converted data) for bixverse and Seurat +
  BPCells.

## Running it

```bash
uv run scripts/subsample.py ~/Desktop/parse_pbmc_1m data/parse_100k 100000
uv run scripts/to_h5ad.py data/parse_100k
REF_bixverse=main scripts/vendor.sh     # local checkouts, per-package refs
docker build -f docker/r.Dockerfile -t scbench-r .
docker build -f docker/py.Dockerfile -t scbench-py .

# tool: bixverse | scanpy | scrapper | seurat_standard | seurat_bpcells | osca
# INPUT: mtx | h5ad | dask (scanpy only)
[INPUT=h5ad] [BIX_KNN=nndescent] [BIX_CSC_GB=8] [TAG=suffix] scripts/run.sh <tool> parse_100k
scripts/run_native.sh parse_100k       # bixverse.gpu on Metal

uv run scripts/tables.py results
```
