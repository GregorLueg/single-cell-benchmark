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

Seconds without tSNE and peak memory (whole run, tSNE included) from h5ad, or
where the run died, plus quality against the truth across the sizes each tool
finished. Stack: bixverse 0.8.1, bixverse.gpu 0.6.1, Scanpy 1.12.4, scrapper
1.6.3, Seurat 5.6.0. One repeat, one seed.

| framework | 100k | 500k | 1M | Harmony purity | ARI | rare F1 |
|---|---|---|---|---|---|---|
| bixverse | 15 s, 1.6 GB | 88 s, 5.7 GB | 190 s, 10.5 GB | 0.969 to 0.970 | 0.79 to 0.98 | 0.26 to 0.35 |
| bixverse GPU (wgpu, native)\* | 12 s, 1.9 GB | 41 s, 5.4 GB | 91 s, 10.9 GB | 0.963 to 0.968 | 0.80 to 0.98 | 0.24 to 0.29 |
| bixverse MLX (native)\* | 9 s, 1.5 GB | 37 s, 6.1 GB | 80 s, 10.9 GB | 0.965 to 0.967 | 0.87 to 0.97 | 0.22 to 0.31 |
| Scanpy | 122 s, 2.6 GB | 766 s, 14.2 GB | OOM at load | 0.894 to 0.908 | 0.78 to 0.88 | 0.09 to 0.11 |
| Scanpy dask (experimental, no DGE) | 77 s, 1.8 GB | 317 s, 7.8 GB | 719 s, 10.8 GB | 0.889 to 0.908 | 0.86 to 0.91 | 0.10 to 0.11 |
| scrapper | 83 s, 5.5 GB | 469 s, 22.7 GB | OOM at load | 0.926 to 0.929 | 0.94 | 0.13 |
| scrapper HDF5 | 223 s, 3.3 GB | 2413 s, 12.3 GB | TIMEOUT at dge | 0.926 to 0.929 | 0.94 | 0.13 |
| Seurat std | 125 s, 8.9 GB | OOM at pca | OOM at load | 0.971 | 0.81 | 0.27 |
| Seurat BPCells | 223 s, 2.5 GB | 1140 s, 6.9 GB | 2305 s, 10.8 GB | 0.968 to 0.971 | 0.70 to 0.79 | 0.27 to 0.35 |

\* Native macOS on Metal, no memory cap, peak is the process memory
footprint: close to, but not the same metric as, the Docker rows. MLX needs an opt-in build against mlx-c.

- **bixverse is about 5x faster than scrapper at a quarter to a third of its
  memory, and 3.6x to 8.7x faster than Scanpy (Dask to h5ad).** At 1M only
  three out-of-core designs finish: bixverse (3.2 min), Scanpy with Dask
  (12 min, no DGE) and Seurat with BPCells (38 min). From 500k the GPU rows
  halve bixverse's time again (native, so their load also skips the VM); at
  100k they save 3 to 6 s.
- **Scanpy Dask skips the slowest Scanpy step.** It has no DGE (Wilcoxon fails
  on Dask arrays); in-memory Scanpy spends 454 s of its 766 s on it at 500k.
- **No compromise on embeddings.** bixverse and Seurat share the top Harmony
  purity (0.97), ahead of scrapper (0.93) and Scanpy (0.89 to 0.91), and the
  best recovery of the rare group, though at rare F1 0.26 to 0.35 nobody
  recovers it well.
- **scrapper clusters best at 500k.** ARI 0.94 at 100k and 500k from its
  rank-weighted sNN (no scores at 1M: it OOMs in memory and times out in DGE
  on HDF5), though it merges groups (9 clusters for 12) and misses the rare
  one. bixverse leads at 100k (0.98) and drops to 0.79 to 0.88,
  depending on whether Leiden returns 12 or 13 clusters.
- **DGE in seconds.** 0.5 to 4.2 s for bixverse, against 3.6 to 23 s for
  scrapper, 46 to 454 s for Scanpy and 57 to 518 s for BPCells. On the shared
  genes it ranks like Seurat's presto; scrapper and Scanpy rank detectable markers slightly
  better.
- **scrapper out of core saves memory, not time.** On HDF5 it stays under
  13 GB without swap at 500k, but takes 2,413 s, most of it in DGE, and
  times out in DGE at 1M and on the full PBMC data.
- **Harmony on the same input:** at 1M bixverse v2 is 2x faster than
  harmonypy 2.1.0 (2.1 against 4.2 s) and MLX 4.2x; at 100k both are 1.8x.
  97% of harmonypy's neighbours kept, at 1.1 GB more memory for v2.
- **Smallest on disk.** bixverse's store takes 2.7 GB at 1M, against 3.7 GB
  for the BPCells store and 8.1 GB for the h5ad. BPCells' DGE step adds a
  gene-major copy of the normalised data, 12.5 GB on disk in all.

## Real data check: PBMC

Seconds without tSNE and peak memory on the Parse 1M PBMC data and random
subsamples, or where the run died. Same stack.

| framework | 100k | 500k | full |
|---|---|---|---|
| bixverse mtx | 18 s, 1.6 GB | 94 s, 6.3 GB | 202 s, 9.5 GB |
| bixverse h5ad | 15 s, 1.7 GB | 73 s, 6.6 GB | 151 s, 8.7 GB |
| bixverse GPU (wgpu, native)\* | 10 s, 2.2 GB | 39 s, 5.9 GB | 81 s, 8.5 GB |
| bixverse MLX (native)\* | 9 s, 1.4 GB | 38 s, 5.9 GB | 75 s, 8.0 GB |
| Scanpy mtx | 137 s, 6.0 GB | OOM at load | OOM at load |
| Scanpy h5ad | 116 s, 2.0 GB | 832 s, 14.2 GB | OOM at load |
| Scanpy dask (experimental, no DGE) | 65 s, 1.6 GB | 237 s, 6.7 GB | 490 s, 10.4 GB |
| scrapper mtx | 102 s, 5.3 GB | OOM at load | OOM at load |
| scrapper h5ad | 66 s, 4.8 GB | 434 s, 20.9 GB | OOM at load |
| scrapper HDF5 | 201 s, 2.7 GB | 2237 s, 8.3 GB | TIMEOUT at dge |
| Seurat std mtx | 141 s, 7.7 GB | OOM at load | OOM at load |
| Seurat std h5ad | 109 s, 7.8 GB | OOM at load | OOM at load |
| Seurat BPCells | 286 s, 2.5 GB | 1421 s, 5.6 GB | 3012 s, 10.9 GB |

The real data agree with the simulation: only the out-of-core designs finish
the full set (bixverse in 2.5 min from h5ad, Scanpy with Dask in 8.2 min
without DGE, Seurat with BPCells in 50 min, all at 8.7 to 10.9 GB), and every
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
- Defaults that favour bixverse: its UMAP optimiser is multi-threaded where
  Scanpy's, Seurat's and scrapper's run on one thread, and its quick tSNE uses
  qdtsne's leaf approximation, which scrapper leaves off. Defaults that favour
  Scanpy: Leiden with 2 iterations, Wilcoxon without tie correction.
- Seurat with BPCells transposes its data to gene-major order inside the DGE
  step, as BPCells advises for `FindAllMarkers`; the time and the extra disk
  count against it.
- Harness workarounds: Scanpy Dask computes its QC sums by hand, because
  `calculate_qc_metrics` blows up under Dask, and has no DGE. scrapper HDF5
  and Scanpy Dask need an h5ad (or 10x `.h5`); their MTX conversion is not
  timed.

Details in [methods](docs/methods.md#caveats).

Think a framework is run the wrong way here, or along a slower path than it
should be? Please [open an issue](https://github.com/GregorLueg/single-cell-benchmark/issues)
with the call you'd use instead. The pipelines are in `pipelines/`.

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
