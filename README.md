# single-cell-benchmark

## Description

How far do single cell frameworks get on a MacBook Air class machine, and do
they still get the right answer? The same eleven step workflow in every
framework (load, QC, normalise, HVG, PCA, Harmony, kNN/sNN, Leiden, UMAP, DGE,
tSNE), in Docker capped at 24 GB and 8 cores to mimic a small laptop.

The main data are Splat simulations of 100k, 500k and 1M cells with
[splatter-sc](https://github.com/GregorLueg/splatter-sc), fitted to real PBMC
data: 24 batches, 12 groups, a rare group in a quarter of the batches. The
truth is known, so every run is scored on clustering, embeddings, batch
integration, HVGs and markers, not just timed. The Parse Biosciences 1M PBMC
data set (987,585 cells) is the real-data check on speed and memory.

Every data set comes as two compressed inputs, the way they sit on most
people's disks: `DGE.mtx.gz` (gzip level 6) and `DGE.h5ad` (gzip level 4, no
shuffle, the layout `sc.write` and `anndata.write_h5ad(compression="gzip")`
give). Decompression counts as part of the load, and every run starts from a
cold file cache. All six data sets take 19 GB on disk.

The benchmarks ran within Docker on a MacBook M1 Max. Next up: the Parse 10M
PBMC data set, see [below](#work-in-progress-parse-10m-pbmc).

## Headline

Seconds without tSNE and peak memory (whole run, tSNE included) from h5ad, or
where the run died, plus quality against the truth across the sizes each tool
finished. Stack: bixverse 0.9.0 (R) and 0.3.1 (Python), Scanpy 1.12.5,
scrapper 1.6.3, Seurat 6.0.0, CyteArc 1.3.0, brisc 0.2.5. One repeat, one seed.

| framework | 100k | 500k | 1M | Harmony purity | ARI | rare F1 |
|---|---|---|---|---|---|---|
| bixverse | 11 s, 1.2 GB | 50 s, 4.3 GB | 109 s, 8.1 GB | 0.969 to 0.970 | 0.86 to 0.98 | 0.26 to 0.35 |
| bixverse-py | 9 s, 0.9 GB | 47 s, 4.2 GB | 106 s, 7.8 GB | 0.969 to 0.970 | 0.87 to 0.98 | 0.26 to 0.35 |
| brisc | 30 s, 0.7 GB | 153 s, 3.1 GB | 317 s, 8.1 GB | 0.974 | 0.88 to 0.98 | 0.28 to 0.34 |
| brisc hogwild | 9 s, 0.7 GB | 45 s, 4.1 GB | 100 s, 8.1 GB | 0.974 | 0.88 to 0.98 | 0.28 to 0.34 |
| Scanpy | 157 s, 2.6 GB | 801 s, 10.8 GB | 2408 s, TIMEOUT in tSNE | 0.889 to 0.908 | 0.83 to 0.90 | 0.09 to 0.11 |
| Scanpy dask (t-test DGE) | 140 s, 3.2 GB | 496 s, 13.4 GB | OOM at dge | 0.894 to 0.908 | 0.84 to 0.90 | 0.05 to 0.11 |
| scrapper | 83 s, 5.5 GB | 480 s, 23.9 GB | OOM at load | 0.927 to 0.929 | 0.94 | 0.13 |
| Seurat std | 124 s, 8.8 GB | OOM at pca | OOM at load | 0.971 | 0.81 | 0.27 |
| Seurat BPCells | 223 s, 2.3 GB | 1163 s, 5.9 GB | 2344 s, TIMEOUT in tSNE | 0.968 to 0.971 | 0.70 to 0.79 | 0.27 to 0.35 |
| CyteArc | 171 s, 6.8 GB | 788 s, 10.9 GB | 1640 s, 10.9 GB | 0.949 to 0.956 | 0.95 to 0.97 | 0.14 to 0.34 |

The bixverse GPU runs (wgpu and MLX) need Metal, so they run natively and sit
in [their own tables](docs/results_1m.md#native-runs-cpu-against-gpu-old-stack),
against the same CPU pipeline run natively. They are still on the previous
stack and get rerun next.

- **bixverse and brisc are in a league of their own.** bixverse is 14x to 22x
  faster than in-memory Scanpy and 7x to 10x faster than scrapper, at a fifth
  of scrapper's memory at 500k. brisc with its multi-threaded Hogwild UMAP is
  level with it on the simulation and a little faster on PBMC; brisc is
  in memory and loads faster, bixverse is out of core and wins UMAP and the
  kNN. brisc's default single-threaded UMAP takes it to 3x the time.
- **At 1M the in-memory heavyweights run out of road.** scrapper and Seurat
  standard OOM at load (Seurat already in PCA at 500k). Scanpy from h5ad
  scrapes through DGE at the 24 GB cap with swap and times out in tSNE.
  bixverse and brisc peak at 8.1 GB, CyteArc at 10.9 GB, BPCells at 11.5 GB.
- **The speed doesn't cut corners.** bixverse lands within the spread of the
  established frameworks on every score: Harmony purity 0.97 (others 0.89 to
  0.97), ARI 0.86 to 0.98 (others 0.70 to 0.98), DGE on the shared genes level
  with Seurat's presto. brisc has the cleanest Harmony embedding and keeps the
  most of the rare group. Every framework runs its own defaults on one seed of
  one simulator, so the scores are a parity check, not a ranking.
- **DGE in seconds, with a test.** 0.5 to 4.1 s for bixverse's Wilcoxon,
  against 3.5 to 22 s for scrapper, 6 to 24 s for CyteArc, 49 to 1,593 s for
  Scanpy and 57 to 533 s for BPCells. brisc's 0.0 to 0.3 s ranks by detection
  rate with no test and ranks detectable markers much worse (R-precision 0.29
  to 0.34 against 0.88 to 0.94). Scanpy dask can only run the t-test.
- **bixverse from Python or R, same thing.** bixverse-py runs the same Rust
  and scores the same; it is 2% to 11% faster without tSNE (load and DGE).
- **CyteArc finishes every size at about 10 GB, slowly.** 171, 788 and
  1,640 s from h5ad; UMAP is about half of its analysis time.
- **Smallest on disk.** bixverse's store takes 2.7 GB at 1M, against 8.3 GB
  for CyteArc's (counts cell- and gene-major) and 12.5 GB for BPCells (with
  the gene-major copy its DGE step writes); the gzipped h5ad is 2.8 GB.

## Real data check: PBMC

Seconds without tSNE and peak memory on the Parse 1M PBMC data and random
subsamples, or where the run died. Same stack.

| framework | 100k | 500k | full |
|---|---|---|---|
| bixverse mtx | 14 s, 1.3 GB | 60 s, 5.0 GB | 123 s, 8.4 GB |
| bixverse h5ad | 11 s, 0.9 GB | 46 s, 5.3 GB | 90 s, 8.5 GB |
| bixverse-py mtx | 12 s, 0.7 GB | 56 s, 5.0 GB | 120 s, 8.0 GB |
| bixverse-py h5ad | 9 s, 0.7 GB | 41 s, 5.0 GB | 85 s, 8.1 GB |
| brisc h5ad | 22 s, 0.7 GB | 115 s, 4.0 GB | 228 s, 8.9 GB |
| brisc h5ad hogwild | 7 s, 0.7 GB | 39 s, 4.4 GB | 77 s, 8.9 GB |
| Scanpy mtx | 169 s, 4.9 GB | OOM at load | OOM at load |
| Scanpy h5ad | 148 s, 2.1 GB | 909 s, 14.2 GB | OOM at load |
| Scanpy dask (t-test DGE) | 128 s, 2.9 GB | 410 s, 11.9 GB | 805 s, 20.2 GB |
| scrapper mtx | 103 s, 5.5 GB | 661 s, 23.9 GB | OOM at load |
| scrapper h5ad | 68 s, 4.8 GB | 438 s, 20.9 GB | OOM at load |
| Seurat std mtx | 143 s, 8.8 GB | OOM at load | OOM at load |
| Seurat std h5ad | 117 s, 7.7 GB | OOM at load | OOM at load |
| Seurat BPCells | 284 s, 2.4 GB | 1459 s, 5.4 GB | 3045 s, 9.5 GB |
| CyteArc mtx | 190 s, 8.1 GB | 860 s, 8.6 GB | 1606 s, 8.3 GB |
| CyteArc h5ad | 162 s, 9.7 GB | 702 s, 9.5 GB | 1347 s, 8.9 GB |

The real data agree with the simulation. On the full set brisc with Hogwild
is fastest (77 s), then bixverse from h5ad (85 s from Python, 90 s from R) at
slightly less memory. The other survivors are all out of core: Scanpy dask in
13 min, CyteArc in 22 min, Seurat with BPCells in 51 min. Every other
in-memory path dies at load. Against in-memory Scanpy at 500k, the largest
size it survives, bixverse is 20x faster at about a third of the memory.
Per-step tables, the per-step memory heatmaps, the warm start and the scaling
figures are in [results](docs/results_1m.md).

## Work in progress: Parse 10M PBMC

The next step up: the [Parse 10M PBMC](https://www.parsebiosciences.com/datasets/10-million-human-pbmcs-in-a-single-experiment/)
data set, 9.7M cells from 12 donors treated with 90 cytokines, in one gzipped
h5ad (44 GB on disk, about 226 GB of counts in memory). Out-of-core designs
only, plus one brisc attempt, at a 48 GB cap and 5 h per run: Harmony on the
donors, Leiden scored against Parse's cell types, DGE for a handful of
cytokines against PBS, UMAP last. Then bixverse on the CPU against wgpu and
MLX. Plan and status in [results_10m](docs/results_10m.md).

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
- Peak memory is cgroup anon only, which favours the out-of-core rows. The
  native GPU rows report the macOS peak footprint without a cap, so they get
  their own tables.
- Docker on macOS runs in a VM: the bixverse CPU pipeline was 1.3x to 1.7x
  faster run natively on the previous stack, mostly in load. The other
  frameworks likely pay a similar tax; only bixverse was run both ways.
- From 500k bixverse's CPU tSNE uses an approximate kNN (IVF), where the
  default Barnes-Hut of Scanpy and Seurat pays for an exact one.
- Defaults that favour bixverse: its UMAP optimiser is multi-threaded where
  Scanpy's, Seurat's, scrapper's and CyteArc's run on one thread. UMAP
  settings (epochs, optimiser, graph weights) are each framework's own. brisc
  gets an extra Hogwild column, which brisc documents as not reproducible.
  Defaults that favour Scanpy: Leiden with 2 iterations, Wilcoxon without tie
  correction.
- Seurat with BPCells transposes its data to gene-major order inside the DGE
  step, as BPCells advises for `FindAllMarkers`; the time and the extra disk
  count against it.
- Two DGE steps are not Wilcoxon: Scanpy dask runs the t-test (Wilcoxon
  fails on Dask arrays) and brisc ranks by detection rate with no test.
- Harness workarounds: Scanpy dask computes its QC sums by hand, because
  `calculate_qc_metrics` blows up under Dask, and needs an h5ad; the MTX
  conversion is not timed. brisc finds MT genes by var name, so on PBMC the
  harness swaps the gene symbols in for its QC.
- scrapper reaches 500k only by swapping at the 24 GB cap.
- Every mtx reader has to inflate one gzip stream, and gzip doesn't split, so
  that part of the load runs on one thread whatever the parser does after.
- The splat h5ads come straight from splatter-sc. They match anndata's layout
  except the `X` chunk length, which splatter-sc sizes from its nonzero
  estimate: within 3% of what h5py would pick.

Details in [methods](docs/methods.md).

Think a framework is run the wrong way here, or along a slower path than it
should be? Please [open an issue](https://github.com/GregorLueg/single-cell-benchmark/issues)
with the call you'd use instead. The pipelines are in `pipelines/`.

## Docs

- [Results up to 1M](docs/results_1m.md): per-step tables, memory heatmaps
  and quality scores for every size, the same-input Harmony comparison, the
  native GPU runs, and what they show.
- [Results at 10M](docs/results_10m.md): the Parse 10M PBMC run, in progress.
- [Methods](docs/methods.md): setup, versions, the simulation, workflow
  parameters, how the scores work, full caveats, how to run it.

## Running it

```bash
# simulation (splatter-sc 0.1.1): writes DGE.mtx.gz and a gzipped DGE.h5ad
python3 scripts/sim_params.py sim/splat_fit.json 100000 data/splat_100k > sim/splat_100k.json
splatter-sc sim/splat_100k.json
# PBMC
uv run scripts/subsample.py ~/Desktop/parse_pbmc_1m data/parse_100k 100000
uv run scripts/to_h5ad.py data/parse_100k

docker build -f docker/r.Dockerfile -t scbench-r .
docker build -f docker/py.Dockerfile -t scbench-py .
scripts/run.sh <tool> splat_100k       # bixverse | bixverse_py | scanpy | scrapper | seurat_standard | seurat_bpcells | cytearc | brisc
uv run scripts/tables.py results
uv run scripts/score.py results/splat_100k data/splat_100k
```

Options, the native GPU run and the Harmony comparison:
[methods](docs/methods.md#running-it).
