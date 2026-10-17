# single-cell-benchmark

## Description

How far do the big single cell frameworks get on a MacBook Air class machine,
and do they still get the right answer? The same eleven step workflow in every
framework (load, QC, normalise, HVG, PCA, Harmony, kNN/sNN, Leiden, UMAP, DGE,
tSNE), in Docker capped at 24 GB and 8 cores to mimic a small laptop.

The main data are Splat simulations of 100k, 500k and 1M cells with
[splatter-sc](https://github.com/GregorLueg/splatter-sc), fitted to real PBMC
data: 24 batches, 12 groups, a rare group in a quarter of the batches. The
truth is known, so every run is scored on clustering, embeddings, batch
integration, HVGs and markers, not just timed. The Parse Biosciences 1M PBMC
data set (987,585 cells) is the real-data check on speed and memory.

The benchmarks ran within Docker on a MacBook M1 Max.

## Headline

Seconds without tSNE and peak memory from h5ad, or where the run died, plus
quality against the truth across the three sizes. Current stack: bixverse
0.6.0, Seurat 5.6.0, harmonypy 2.1.0. One repeat, one seed.

| framework | 100k | 500k | 1M | Harmony purity | ARI | rare F1 |
|---|---|---|---|---|---|---|
| bixverse | 17 s, 1.5 GB | 87 s, 5.7 GB | 209 s, 11.4 GB | 0.969 to 0.970 | 0.78 to 0.87 | 0.24 to 0.32 |
| bixverse GPU (native)\* | 11 s, 4.1 GB | 44 s, 13.0 GB | 108 s, 17.8 GB | 0.963 to 0.965 | 0.78 to 0.82 | 0.22 to 0.29 |
| Scanpy | 125 s, 3.0 GB | 769 s, 16.2 GB | OOM at load | 0.894 to 0.908 | 0.78 to 0.88 | 0.09 to 0.11 |
| Scanpy dask (no DGE) | 79 s, 2.4 GB | 320 s, 5.4 GB | 727 s, 11.0 GB | 0.889 to 0.908 | 0.86 to 0.91 | 0.10 to 0.11 |
| scrapper | 100 s, 5.4 GB | 533 s, 22.7 GB | OOM at load | 0.927 to 0.928 | 0.94 | 0.13 |
| Seurat std | 124 s, 8.9 GB | OOM at pca | OOM at load | 0.971 | 0.81 | 0.27 |
| Seurat BPCells | 255 s, 2.5 GB | 1268 s, 6.5 GB | 2636 s, 8.2 GB | 0.968 to 0.971 | 0.70 to 0.79 | 0.27 to 0.35 |
| OSCA HDF5 | OOM (worker) at pca | - | - | - | - | - |

\* Native macOS on Metal, no memory cap, peak is process RSS: not comparable
to the Docker rows!

- **bixverse is about 6x faster than scrapper at a quarter of its memory, and
  3.5x to 9x faster than Scanpy (Dask to h5ad).** At 1M only the out-of-core designs are
  left: bixverse (3.5 min), Scanpy with Dask (12 min, no DGE) and Seurat with
  BPCells (44 min).
- **No compromise on embeddings.** bixverse and Seurat share the top Harmony
  purity (0.97), ahead of scrapper (0.93) and Scanpy (0.89 to 0.91), and the
  best recovery of the rare group.
- **scrapper clusters best.** Native ARI 0.94 at every size from its
  rank-weighted sNN; bixverse and Seurat prune a Jaccard sNN and over-split.
- **DGE in seconds.** 0.5 to 3.4 s for bixverse, against 4 to 23 s for scrapper
  and minutes for Scanpy and BPCells. At 100k it ranks the shared genes
  exactly like Seurat's presto.
- **Harmony on the same input:** bixverse v2 2x faster than harmonypy 2.1.0,
  same output, 1.1 GB more memory at 1M.
- **Disk is the price.** bixverse keeps two on-disk views: 13.2 GB at 1M,
  against 3.7 GB for BPCells.

## Real data check: PBMC

Seconds from load to UMAP (tSNE excluded) and peak memory on the Parse 1M PBMC
data and random subsamples, or where the run died. Older stack: bixverse
0.5.5, Seurat 5.5.1, harmonypy 2.0.2, no DGE step (TODO: rerun on the released
versions).

| framework | 100k | 500k | full |
|---|---|---|---|
| bixverse mtx | 25 s, 1.6 GB | 150 s, 6.3 GB | 307 s, 9.8 GB |
| bixverse h5ad | 20 s, 1.7 GB | 110 s, 6.5 GB | 238 s, 8.9 GB |
| bixverse GPU (native)\* | 12 s, 4.2 GB | 56 s, 10.0 GB | 127 s, 15.6 GB |
| Scanpy mtx | 93 s, 6.8 GB | OOM at load | OOM at load |
| Scanpy h5ad | 76 s, 2.6 GB | 297 s, 14.2 GB | OOM at load |
| Scanpy dask | 74 s, 1.9 GB | 294 s, 6.8 GB | 629 s, 9.5 GB |
| scrapper mtx | 102 s, 5.3 GB | OOM at load | OOM at load |
| scrapper h5ad | 65 s, 4.8 GB | 519 s, 22.7 GB | OOM at load |
| Seurat std mtx | 185 s, 8.7 GB | OOM at load | OOM at load |
| Seurat std h5ad | 144 s, 8.7 GB | OOM at load | OOM at load |
| Seurat BPCells | 196 s, 1.9 GB | 1091 s, 5.5 GB | 2310 s, 9.7 GB |
| OSCA HDF5 | 807 s, 22.7 GB | OOM (worker) at hvg | OOM (worker) at hvg |

The real data agree with the simulation: only the out-of-core designs finish
the full set (bixverse in 4.0 min from h5ad, Scanpy with Dask in 10.5 min,
Seurat with BPCells in 38.5 min, all at 9 to 10 GB), and every in-memory path
dies at load. Per-step tables, the warm start and the scaling figures are in
[results](docs/results.md#pbmc).

## Caveats

- One repeat, one machine (M1 Max under Docker, VM limit ~23.4 GB plus ~4 GB
  swap), one simulation seed. Single-run Leiden ARI moves by up to 0.1 on
  near-identical embeddings; purity is the stable score.
- Splat is the easy case: no gene-gene structure, convex groups, a batch
  effect on every gene. The quality scores rank pipelines on that, not on
  real data.
- Defaults differ between frameworks (scaling before PCA, normalisation,
  graph construction), so cluster counts do not compare.
- Harness workarounds: Scanpy Dask computes its QC sums by hand, because
  `calculate_qc_metrics` blows up under Dask, and has no DGE, as Wilcoxon
  fails on Dask arrays; OSCA runs its documented parallel path, which OOMs.
- The benchmark is written by bixverse's author.

TODO, before this goes public:

- bixverse 0.6.0 and bixverse.gpu run from local checkouts (bixverse-rs from
  its `release-0.6.0` branch, plus a one-line CellPhoneDB patch); switch to
  the r-universe releases. Details in
  [methods](docs/methods.md#versions).
- The PBMC tables and figures predate the DGE step and the current versions;
  rerun them.

Details in [methods](docs/methods.md).

## Docs

- [Results](docs/results.md): per-step tables and quality scores for every
  size, the same-input Harmony comparison, and what they show.
- [Methods](docs/methods.md): setup, versions, the simulation, workflow
  parameters, how the scores work, full caveats, how to run it.

## Running it

```bash
# simulation (splatter-sc 0.1.0)
python3 scripts/sim_params.py sim/splat_fit.json 100000 data/splat_100k > sim/splat_100k.json
splatter-sc sim/splat_100k.json
# PBMC
uv run scripts/subsample.py ~/Desktop/parse_pbmc_1m data/parse_100k 100000
uv run scripts/to_h5ad.py data/parse_100k

docker build -f docker/r.Dockerfile -t scbench-r .
docker build -f docker/py.Dockerfile -t scbench-py .
scripts/run.sh <tool> splat_100k       # bixverse | scanpy | scrapper | seurat_standard | seurat_bpcells | osca
uv run scripts/tables.py results
uv run scripts/score.py results/splat_100k data/splat_100k
```

Options, the native GPU run and the Harmony comparison:
[methods](docs/methods.md#running-it).
