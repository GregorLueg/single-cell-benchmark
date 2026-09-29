# Methods

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
