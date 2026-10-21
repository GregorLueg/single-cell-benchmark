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
quality against the truth across the three sizes. Stack: bixverse 0.8.0,
bixverse.gpu 0.6.0, Scanpy 1.12.4, scrapper 1.6.3, Seurat 5.6.0. One repeat,
one seed.

| framework | 100k | 500k | 1M | Harmony purity | ARI | rare F1 |
|---|---|---|---|---|---|---|
| bixverse | 16 s, 1.7 GB | 93 s, 5.7 GB | 218 s, 10.5 GB | 0.969 to 0.970 | 0.88 to 0.98 | 0.26 to 0.35 |
| bixverse GPU (wgpu, native)\* | 12 s, 2.0 GB | 47 s, 5.6 GB | 112 s, 10.7 GB | 0.963 to 0.968 | 0.80 to 0.98 | 0.23 to 0.30 |
| bixverse MLX (native)\* | 10 s, 1.5 GB | 40 s, 6.2 GB | 83 s, 11.4 GB | 0.965 to 0.967 | 0.80 to 0.97 | 0.22 to 0.31 |
| Scanpy | 122 s, 2.6 GB | 766 s, 14.2 GB | OOM at load | 0.894 to 0.908 | 0.78 to 0.88 | 0.09 to 0.11 |
| Scanpy dask (experimental, no DGE) | 77 s, 1.8 GB | 317 s, 7.8 GB | 719 s, 10.8 GB | 0.889 to 0.908 | 0.86 to 0.91 | 0.10 to 0.11 |
| scrapper | 90 s, 5.6 GB | 515 s, 22.7 GB | OOM at load | 0.926 to 0.929 | 0.94 | 0.13 |
| scrapper HDF5 | 213 s, 3.4 GB | 2426 s, 12.4 GB | TIMEOUT at dge | 0.926 to 0.929 | 0.94 | 0.13 |
| Seurat std | 124 s, 8.9 GB | OOM at pca | OOM at load | 0.971 | 0.81 | 0.27 |
| Seurat BPCells | 253 s, 2.6 GB | 1281 s, 6.5 GB | 2662 s, 9.5 GB | 0.968 to 0.971 | 0.70 to 0.79 | 0.27 to 0.35 |

\* Native macOS on Metal, no memory cap, peak is the process memory
footprint: close to, but not the same metric as, the Docker rows. MLX needs an opt-in build against mlx-c.

- **bixverse is about 5.5x faster than scrapper at a quarter of its memory, and
  3.4x to 8x faster than Scanpy (Dask to h5ad).** At 1M only the out-of-core
  designs are left: bixverse (3.6 min), Scanpy with Dask (12 min, no DGE) and
  Seurat with BPCells (44 min). The GPU rows halve bixverse's time again.
- **Scanpy Dask skips the slowest Scanpy step.** It has no DGE (Wilcoxon fails
  on Dask arrays); in-memory Scanpy spends 454 s of its 766 s on it at 500k.
- **No compromise on embeddings.** bixverse and Seurat share the top Harmony
  purity (0.97), ahead of scrapper (0.93) and Scanpy (0.89 to 0.91), and the
  best recovery of the rare group.
- **scrapper clusters best from 500k.** ARI 0.94 at every size from its
  rank-weighted sNN, though it merges groups (9 clusters for 12) and misses
  the rare one. bixverse leads at 100k (0.98) and drops to 0.88.
- **DGE in seconds.** 0.5 to 5.4 s for bixverse, against 3.5 to 22 s for
  scrapper and minutes for Scanpy and BPCells. On the shared genes it ranks
  like Seurat's presto; scrapper and Scanpy rank detectable markers slightly
  better.
- **scrapper out of core saves memory, not time.** On HDF5 it stays under
  13 GB without swap at 500k, but takes 2,426 s, most of it in DGE, and
  times out in DGE at 1M and on the full PBMC data.
- **Harmony on the same input:** bixverse v2 2x faster than harmonypy 2.1.0
  (2.1 against 4.2 s at 1M), MLX 4.2x, with 97% of harmonypy's neighbours
  kept, at 1.1 GB more memory for v2.
- **Disk is the price.** bixverse keeps two on-disk views: 13.2 GB at 1M,
  against 3.7 GB for BPCells.

## Real data check: PBMC

Seconds without tSNE and peak memory on the Parse 1M PBMC data and random
subsamples, or where the run died. Same stack.

| framework | 100k | 500k | full |
|---|---|---|---|
| bixverse mtx | 19 s, 1.6 GB | 97 s, 6.4 GB | 202 s, 9.5 GB |
| bixverse h5ad | 15 s, 1.7 GB | 78 s, 6.5 GB | 180 s, 8.9 GB |
| bixverse GPU (wgpu, native)\* | 10 s, 2.1 GB | 52 s, 6.1 GB | 113 s, 8.8 GB |
| bixverse MLX (native)\* | 10 s, 1.5 GB | 45 s, 6.1 GB | 82 s, 8.4 GB |
| Scanpy mtx | 137 s, 6.0 GB | OOM at load | OOM at load |
| Scanpy h5ad | 116 s, 2.0 GB | 832 s, 14.2 GB | OOM at load |
| Scanpy dask (experimental, no DGE) | 65 s, 1.6 GB | 237 s, 6.7 GB | 490 s, 10.4 GB |
| scrapper mtx | 104 s, 5.3 GB | OOM at load | OOM at load |
| scrapper h5ad | 73 s, 4.9 GB | 565 s, 22.9 GB | OOM at load |
| scrapper HDF5 | 201 s, 2.5 GB | 2182 s, 8.3 GB | TIMEOUT at dge |
| Seurat std mtx | 143 s, 7.7 GB | OOM at load | OOM at load |
| Seurat std h5ad | 110 s, 7.8 GB | OOM at load | OOM at load |
| Seurat BPCells | 361 s, 2.6 GB | 1829 s, 5.6 GB | 3231 s, 9.5 GB |

The real data agree with the simulation: only the out-of-core designs finish
the full set (bixverse in 3.0 min from h5ad, Scanpy with Dask in 8.2 min
without DGE, Seurat with BPCells in 54 min, all at 9 to 10 GB), and every
in-memory path dies at load. Per-step tables, the warm start and the scaling
figures are in [results](docs/results.md#pbmc).

## Caveats

- The benchmark is written by bixverse's author. The methods list every bias
  found, including the ones that favour bixverse.
- One repeat, one machine (M1 Max under Docker, VM limit ~23.4 GB plus ~4 GB
  swap), one simulation seed. Reruns moved bixverse's load by up to 35 s.
- Splat is the easy case: no gene-gene structure, convex groups, a batch
  effect on every gene. The quality scores rank pipelines on that, not on
  real data.
- Defaults differ between frameworks (scaling before PCA, normalisation,
  graph construction), so cluster counts do not compare.
- Peak memory is cgroup anon only, which favours the out-of-core rows; the
  GPU and MLX rows run natively without a cap.
- From 500k bixverse's CPU tSNE uses an approximate kNN (IVF), where the
  default Barnes-Hut of Scanpy and Seurat pays for an exact one.
- Harness workarounds: Scanpy Dask computes its QC sums by hand, because
  `calculate_qc_metrics` blows up under Dask, and has no DGE. scrapper HDF5
  and Scanpy Dask need an h5ad (or 10x `.h5`); their MTX conversion is not
  timed.

Details in [methods](docs/methods.md#caveats).

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
scripts/run.sh <tool> splat_100k       # bixverse | scanpy | scrapper | seurat_standard | seurat_bpcells
uv run scripts/tables.py results
uv run scripts/score.py results/splat_100k data/splat_100k
```

Options, the native GPU run and the Harmony comparison:
[methods](docs/methods.md#running-it).
