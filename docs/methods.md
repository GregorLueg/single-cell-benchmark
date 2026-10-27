# Methods

## Setup

- **Machine**: M1 Max, Docker Desktop, containers capped at
  `--cpus=8 --memory=24g`. The VM itself has ~23.4 GB plus ~4 GB swap, and that
  is the limit that actually bites. Slightly stricter than an Air.
- **GPU**: Docker has no Metal access, so the bixverse GPU rows run natively on
  macOS (`scripts/run_native.sh`). No memory cap there. Its peak is the
  process's peak memory footprint from `/usr/bin/time -l`: dirty anonymous
  and compressed memory plus the process's Metal allocations, but not clean
  file-backed pages, so like cgroup anon it does not charge the mapped
  bixverse store. Max RSS, which does, is much higher (1M simulation:
  17.4 against 10.9 GB on wgpu). Close to the Docker numbers but not the same
  metric, and its disk I/O skips the VM, so its load is faster too. Two
  backends of bixverse.gpu: wgpu (the GPU row) and MLX (the MLX row).
- **MLX**: experimental, and not what a user gets from a plain install. The
  MLX backend is opt-in at build time: it needs mlx-c installed as a system
  library (`brew install mlx-c`, here mlx-c 0.7.0 against MLX 0.32.3) and
  bixverse.gpu built with `BIXVERSE_GPU_MLX=true`. Apple Silicon only. PCA,
  Harmony, the kNN, the fast clustering's k-means, UMAP and tSNE run on MLX;
  Leiden, DGE and the loaders are the same CPU code as the GPU row.
- **Memory**: cgroup `anon` sampled once a second (`docker/monitor.sh`). Page
  cache is excluded, so streaming tools are not charged for their files. This
  favours the out-of-core rows (bixverse, Seurat BPCells, Scanpy Dask,
  scrapper HDF5, CyteArc): the file pages they read or map do not count, while an
  in-memory row pays for every byte it holds. The cgroup cap counts cached
  pages too and reclaims them under pressure, so it still bounds every run.
- **Disk**: `run.sh` records what a run leaves in its scratch volume
  (`scratch_kb`): the bixverse store and the BPCells matrix dirs. Input files
  are not counted. For bixverse and CyteArc that is the store written at load
  (CyteArc's holds the counts twice, cell-major and gene-major). For
  BPCells it also holds the gene-major copy of the normalised data that the
  DGE step writes (see Workflow): the store alone, measured right after load
  (`LOAD_ONLY=1`), is 3.7 GB on 1M simulated cells, against 12.5 GB after a
  full run.
- **Watchdog**: a run is killed when no step finishes for `STEP_TIMEOUT`
  seconds (45 min by default). The tables mark it as **TIMEOUT**.
- **Repeats**: one per run. Treat differences of a few seconds as noise.
- **bixverse**: loaders run at their default `csc_mem_gb = 8`; the sNN kNN is
  nndescent (`BIX_KNN=nndescent`). Every framework's sNN kNN is approximate
  (Annoy or NNDescent), so this is like for like. The GPU and MLX rows use GPU
  NNDescent (`find_neighbours_gpu_sc`).
- **Scanpy Dask**: X read lazily from the h5ad in 50k cell CSR chunks, threaded
  scheduler. `sc.pp.calculate_qc_metrics` peaks at 16.6 GB transiently on 500k
  cells under Dask, whatever the chunk size, and kills the full data set. The
  Dask row therefore computes the three per-cell QC sums with `map_blocks`
  instead (6.2 GB peak, same cells kept). Everything else is stock Scanpy.
- **scrapper HDF5**: the scrapper pipeline on the h5ad read out of core as
  `HDF5Array::H5ADMatrix`. `beachmat.hdf5` hands scrapper a native tatami
  matrix, so QC, HVG, PCA and DGE stream from the file. Pre-filter by
  DelayedArray block processing. The Bioconductor (OSCA) stack on the same
  matrix is not benchmarked; see the caveats. Input restriction: HDF5Array
  reads h5ad (`H5ADMatrix`) and the Cell Ranger `.h5` (`TENxMatrix`, the same
  seed class) out of core, but nothing in this stack streams MTX. An MTX-only
  source (Parse, the MTX directory of Cell Ranger) has to be read into memory
  and written to HDF5 first; that conversion is not timed here, as for the
  Scanpy Dask row, which also needs an h5ad.
- **CyteArc**: imports the mtx or h5ad into its Zarr store at load
  (`MtxToZarr`, `H5adToZarr`), then streams every count pass from it. Its own
  Python 3.13 image (`docker/cytearc.Dockerfile`). Memory budget and workers
  at its defaults, which read the cgroup limits: 17.6 GB (75% of the cap) and
  8 workers. The budget plans block sizes; it is not a hard cap. Every result
  is written to the store as an artifact, and that I/O is in the step times.
  The harness calls the explicit chain (`features.hvgs`, `features.normalize`,
  `reduction.pca`, ...) rather than the `ds.pipeline.rna` recipe, which adds
  cell cycle, doublet scores and four Leiden resolutions; the order and the
  inputs of each call follow the recipe.

## Data

**Simulation**: [splatter-sc](https://github.com/GregorLueg/splatter-sc)
v0.1.0, a streaming Rust port of splatter's Splat simulator. It writes the
Parse layout and an h5ad, plus the truth (`cells_truth.tsv.gz`: batch and
group per cell; `genes_truth.tsv.gz`: DE factors per group).

1. `scripts/estimate_splat.R` fits `splatter::splatEstimate` (splatter 1.32.0)
   on 5,000 PBMC cells that pass the benchmark QC, so means, library sizes and
   dispersion look like the PBMC data (`sim/splat_fit.json`).
2. `scripts/sim_params.py` adds the structure: 24 batches, 12 groups, seed 42.
   Group composition varies per batch (`batch.groupProb`): the smallest group
   sits in only 6 batches (about 1% of cells), another is missing from 8.
   `de.prob = 0.03`, `de.facLoc = 1.5`, `batch.facScale = 0.5`. The fitted
   `bcv.common` (0.36) buries splatter's default DE (`facLoc = 0.1` gives
   ARI 0.004); these values were tuned on 10k cells to leave visible batch
   effects and non-trivial clustering.
3. Three sizes, the same parameters: 100k, 500k and 1M cells (96,342, 482,409
   and 964,763 after QC). The simulation has no MT genes, so the MT filter
   is a no-op there.

**Parse 1M PBMC**: 987,585 cells, 60,664 genes, 24 samples, plus random 100k
and 500k cell subsamples (`scripts/subsample.py`, seed 42). The mtx rows read
the Parse mtx; the h5ad rows read `scripts/to_h5ad.py` output. That
conversion runs once, outside the timings, and is in memory; every h5ad row
(bixverse, Scanpy, Scanpy Dask, scrapper, scrapper HDF5, Seurat) is spared
it. Only the mtx rows pay for parsing text.

## Versions

Every row, PBMC and simulation, runs on the same stack.

| framework | versions |
|---|---|
| bixverse | bixverse 0.8.1 (`feat-new-bixverse-rs` bfd56e1), bixverse.gpu 0.6.1 (`fix-windows` 5d86cb4), bixverse-rs 0.9.0, manifoldsR 0.5.0 (manifolds-rs 0.7.2) |
| Scanpy | 1.12.4 (anndata 0.13.4, dask 2026.8.0, harmonypy 2.1.0, openTSNE 1.0.4, scikit-learn 1.9.1) |
| scrapper | 1.6.3 |
| Seurat | 5.6.0 (SeuratObject 5.4.0, BPCells 0.3.1, harmony 2.0.5, presto 1.1.0, uwot 0.2.5) |
| scrapper HDF5 | scrapper 1.6.3, HDF5Array 1.40.0, DelayedArray 0.38.2, beachmat.hdf5 1.10.0 |
| CyteArc | 1.3.0 (PyPI), Python 3.13 |

bixverse, bixverse.gpu and manifoldsR are built from source: bixverse and
bixverse.gpu at the commits in the table, manifoldsR at the commit in
`vendor/SHAS`. bixverse.gpu uses the bixverse-rs 0.9.0 crates; bixverse
patches them to the `feat-sc-data-improv` branch (93bf560), which the 0.9.0
release contains. The single cell store is the v4 format. The GPU and MLX
rows use the default PCA solver, block Lanczos. Docker:
`docker/r-local.Dockerfile` on top of `scbench-r`. Native: installed into
`rlib/`, bixverse.gpu with the MLX backend.

## Workflow

Same steps and parameters everywhere, each along the framework's standard
in-memory or out-of-core workflow from its vignettes. Some frameworks
document other routes for large data that are not benchmarked here:
scrapper's batch correction via `block =` plus MNN, Seurat's sketching.

1. **load**: pre-filter as bixverse does it. Genes in at least 5 cells first,
   then cells with at least 100 genes and 250 UMIs. bixverse fuses the
   log-normalisation into this streaming pass, so it has no separate
   normalise step.
2. **qc**: MT < 5%, total UMIs >= 750, detected genes >= 250.
3. **normalise**: library size to 1e4 and log1p (bixverse, Scanpy, Seurat);
   centred size factors and log2 (scrapper defaults); CyteArc's default,
   library size to 1000 over the HVGs and log1p, computed lazily, so it runs
   after HVG selection and its cost lands in PCA.
4. **hvg**: 2000 genes, each framework's default method.
5. **pca**: 30 components on the HVGs (scrapper via `runPca(subset =)`, as in
   its vignette). Scanpy and scrapper centre only; Seurat, bixverse and
   CyteArc also scale to unit variance.
6. **harmony**: by sample. Scanpy runs harmonypy with `ncores = 8`, the CPU
   cap; Seurat calls `setThreads(8)`, as its 5.6.0 kernels default to one
   thread. CyteArc runs its own Harmony2 (`reduction.harmony`).
7. **knn_snn**: k = 15. scrapper builds the kNN once (`findKNN` with Annoy)
   and hands it to both `buildSnnGraph` and `runUmap`, as
   `runAllNeighborSteps` in its vignette does; the harness calls the steps one
   by one to keep the per-step times. CyteArc: hnswlib index, k = 15
   neighbours and its fuzzy connectivity graph.
8. **cluster**: Leiden, resolution 1. The graphs differ, so the cluster counts
   do not compare: Scanpy and CyteArc cluster a UMAP-style fuzzy graph, Seurat and bixverse a
   Jaccard sNN pruned at 1/15 and 1/16, scrapper a rank-weighted sNN
   without pruning.
   - `cluster_fast (qd)`: k-means on the Harmony embedding down to
     4 x sqrt(n) centroids, a graph over the centroids (k = 15), Leiden at
     resolutions 1 and 2 on the same k-means, and each cell takes its
     centroid's label. The step time covers k-means and both Leiden runs.
     sqrt(n), the IVF and bluster `TwoStepParam` default, left the rare group
     merged with three neighbours at 100k (rare F1 0.09); 4 x sqrt(n) separates
     it (0.27 against 0.26 for plain Leiden on bixverse). Coarsening still trades resolution for speed:
     a group needs a few centroids of its own to survive. bixverse
     `fast_cluster_sc` (`fast_cluster_gpu_sc` on the GPU and MLX rows, k-means
     on the device); the centroid graph and k-means settings are each
     package's defaults otherwise. scrapper has no single call for it, so the
     harness composes `clusterKmeans`, `buildSnnGraph` on the centroids and
     `clusterGraph`, as bluster's `TwoStepParam` does. An extra row: not in
     the totals. CyteArc has no equivalent.
9. **umap**: defaults. CyteArc's step includes its k-means initialisation
   (`embeddings.initialization`) on the Harmony coordinates, as its recipe does.
10. **dge**: one-vs-rest markers, each framework's default test: bixverse
    `find_all_markers_sc` (Wilcoxon, `min_prop = 0.05`), Scanpy
    `rank_genes_groups` (Wilcoxon), Seurat `FindAllMarkers` (presto),
    scrapper `scoreMarkers` (AUC), CyteArc `markers.search` (Mann-Whitney,
    scored by AUC as for scrapper; genes in at least 5 cells, groups frozen
    from the cell column with `snapshot_cluster_labels`). On BPCells, `FindAllMarkers` does not use
    presto but `BPCells::marker_features` once per group, which wants
    gene-major storage and otherwise warns and transposes on every call. The
    BPCells row therefore transposes the normalised data layer once with
    `transpose_storage_order`, as the warning advises, inside the DGE step:
    its time and its disk copy count against BPCells. It cut DGE from 404 to
    260 s on the 500k simulation and from 1,348 to 1,137 s on the full PBMC
    data, at 0.4 to 1.4 GB more peak memory and three times the disk. On the simulation the groups are
    the true ones, so this tests the DE engine rather than the clustering. On
    PBMC they are the 24 samples, the same workload for everyone.
11. **tsne**: perplexity 30, each tSNE builds its own kNN at k = 3 x
    perplexity.
    - `tsne_default`: each framework's standard Barnes-Hut.
    - `tsne_fft`: FFT where it exists (bixverse `fft_3k`, `fft_3k_gpu` on the
      GPU, Seurat's FIt-SNE, openTSNE for Scanpy).
    - `tsne_quick (qd)`: the quick-and-dirty Barnes-Hut of qdtsne (depth-capped
      tree) at scrapper's defaults: theta 1, 500 iterations, 250 early
      exaggeration at 12, max depth 7, and qdtsne's leaf approximation
      (repulsion once per leaf). bixverse's `bh_qd` uses it by default;
      scrapper's `runTsne` needs `leaf.approximation = TRUE`, which the harness
      sets (it cuts scrapper's step from 151 to 132 s on the 500k simulation).
      bixverse's own defaults (1,000 iterations) are overridden to match. scrapper and
      bixverse (`manifoldsR::tsne(approx_type = "bh_qd")`, and `"bh_qd"` on
      the GPU). Not a standard tSNE.
    - CyteArc has no tSNE row. Its only tSNE is SG-t-SNE-Pi on the
      connectivity graph (no perplexity), comparable to none of the above, and
      its `sgtsnepi` dependency has no linux/arm64 wheel.

On the simulation the score inputs (clusters, HVGs, embeddings, markers) are
written right after DGE, so a tSNE timeout only loses the tSNE rows.

The warm start (`WARM=1`) times only the reconnect: `load_existing` for
bixverse, `open_matrix_dir` plus `CreateSeuratObject` for Seurat + BPCells. It
needs a cold run of the same tool and data set first, and lives in
`<tool>_warm`.

Inside tSNE the bixverse CPU runs use kmknn at 100k and IVF (default `n_list`,
`n_probes`) from 500k up (`BIX_TSNE_KNN=ivf`). kmknn takes 1.7 s at 100k but
49 s at 500k and 182 s on the full PBMC data. This is the one per-size choice
in the harness; every other tool's tSNE runs its default kNN:

| tSNE | implementation | kNN |
|---|---|---|
| Scanpy `tsne_default` | scikit-learn `TSNE` (MulticoreTSNE not installed) | `NearestNeighbors(algorithm = "auto")`, exact |
| Scanpy `tsne_fft` | openTSNE 1.0.4 | `neighbors = "auto"`: Annoy from 1,000 points |
| Seurat `tsne_default` | Rtsne 0.17 | exact VP tree (bhtsne) |
| Seurat `tsne_fft` | FIt-SNE via `fftRtsne` | Annoy (`ann_not_vptree = TRUE`) |
| scrapper `tsne_quick` | qdtsne | Annoy (`BNPARAM = AnnoyParam()`) |
| bixverse GPU / MLX | bixverse.gpu `tsne_gpu_sc` | GPU IVF (`knn_method` default) |

So at 500k and above bixverse gets an approximate kNN where Scanpy's and
Seurat's default Barnes-Hut pay for an exact one. For UMAP, bixverse, Scanpy
and scrapper reuse the k = 15 neighbours; Seurat rebuilds them.

## Quality scores

`scripts/score.py` scores every run on a simulated data set against the
truth. Embedding scores use a 50k cell subsample at larger sizes.

- **Clustering**: ARI and NMI against the true groups; per-group F1 of the
  best-matching cluster, and its value for the smallest group (rare F1).
- **Embeddings** (PCA, Harmony, UMAP, tSNE): share of the 15 nearest
  neighbours in the same true group (purity), overall and for the rare group.
  For PCA and Harmony also: group silhouette; batch mixing, the batch entropy
  of each cell's neighbours over that of 15 random cells of its own group
  (1 is perfect mixing given the uneven composition); and a probe ARI from
  the same Leiden on every embedding.
- **HVGs**: share of the selected genes that are DE in some group.
- **DGE**: true up-regulated markers per group (`DEFacGroup > 1`). AUROC and
  R-precision over all genes, where genes a tool did not report rank last, so
  its filters count; the same on the genes every tool reported (shared), so
  only the ranking counts; and against detectable markers only, those
  detected in at least 10% of their own group's cells.

Probe ARI from a single Leiden run swings by up to 0.1 on near-identical
embeddings, as does native ARI between Seurat standard and BPCells, which run
the same code. Purity and batch mixing are the stable scores.

## Same-input Harmony

`scripts/harmony_bench/` times Harmony on its own: every implementation gets
the same input, bixverse's 30 PC PCA of the 100k and 1M simulations plus
the true batch labels. Each run is its own process, 8 threads (Rayon for
bixverse, `ncores = 8` for harmonypy), native, 3 repeats. The time covers the
Harmony call only; extra memory is the peak RSS over a load-only run.
bixverse v1 (`rs_harmony`), v2 (`rs_harmony_v2`) and the GPU path
(`rs_harmony_v2_gpu`) are called with the same preprocessing as their
wrappers. Defaults throughout; v2 at harmonypy's `block_size = 0.05` is a
matched extra. The outputs go through `score.py` and a kNN overlap against
harmonypy.

## Caveats

- **Written by bixverse's author.** The harness, the parameter choices and
  this text come from the maintainer of bixverse; the caveats below try to
  name every place that favours it.
- **One repeat, one machine, one simulation seed.** Apple Silicon under
  Docker, not a real 24 GB laptop. Reruns of the same bixverse configuration
  moved the load step by up to 35 s, mostly in the MTX reader's file passes.
- **Peak memory includes tSNE.** For bixverse at 1M the tSNE step sets the
  run peak (10.5 against 8.3 GB before tSNE, h5ad).
- **Splat is the easy case.** No gene-gene structure beyond the DE, no
  continuous states, convex groups of similar density, and a multiplicative
  batch effect on every gene. The quality scores rank pipelines on that, not
  on real data.
- **Uncorrected batch mixing is not a quality score.** HVG selectors that
  keep well-expressed genes (scrapper) see more of Splat's per-gene
  batch effect, as well as more of the group signal.
- **GPU and MLX keep less of the rare group at 1M.** Harmony rare purity
  on the GPU rows is about 0.23 against 0.29 on the CPU at 1M, and Harmony
  itself is not the cause (same-input comparison); which step is, is not
  checked.
- **Cluster counts flip between 12 and 13 at 500k and 1M.** Across rows and
  reruns with the same embedding quality, Leiden returns 12 or 13 clusters,
  and ARI moves with it (about 0.87 against 0.79). It is not tested across
  Leiden seeds.
- **Harness code.** The R pre-filter for scrapper and Seurat standard counts
  detections from the sparse slots, but subsetting the matrix still copies
  it; part of their in-memory OOMs may be ours. The Scanpy Dask QC is
  hand-written (see Setup).
- **BPCells DGE includes a transpose.** See Workflow, step 10. Without it
  `FindAllMarkers` on BPCells transposes once per group and is slower; with
  it the step writes a gene-major copy of the data (7.7 GB on the full PBMC
  data). The split between transpose and marker test is not timed.
- **No DGE for Scanpy Dask.** Wilcoxon `rank_genes_groups` fails on Dask
  arrays in Scanpy 1.12.4 (numba `TypingError` in `_select_top_n`). Only the
  t-test runs, and a t-test on zero-inflated counts is not a like-for-like
  substitute, so the Dask row has no DGE step. Its totals are not
  like-for-like: the same step takes in-memory Scanpy 454 s on the 500k
  simulation and 602 s on PBMC 500k. Treat the Dask row as experimental.
- **`cluster_fast` on the CPU is slower than the Leiden it replaces** from
  500k (bixverse 14 against 4 s at 500k, 47 against 8 s at 1M; scrapper 194
  against 123 s). It is in the tables as an option, not in the totals.
- **scrapper HDF5 times out in DGE at the largest size.** On the 1M
  simulation and the full PBMC data no step finished within 45 min after
  UMAP; its row there is marked TIMEOUT.
- **No OSCA row.** The Bioconductor stack (scuttle, scran, scater) on the
  same HDF5-backed matrix does not finish HVG at any size from 500k up within
  45 min, and its forked workers OOM at 100k in PCA and DGE. Its row-wise
  kernels (`modelGeneVar`, `scoreMarkers`) see a delayed, non-pristine matrix
  after `logNormCounts`, so beachmat falls back to R-level block processing,
  and HDF5Array's CSC extractor loads every column for each row block of the
  cell-major file. scran 1.40 and scuttle 1.22 deprecate these functions in
  favour of scrapper, which is the scrapper HDF5 row.
- **Scanpy pays a first-run cost.** Each run is a fresh container, so numba
  compiles its kernels every time; the numba cache is partial and lost with
  the container. This is what a user running the pipeline once sees, and it
  is left in. Scanpy's kNN shows a fixed cost (27 s at 100k, 33 s at 500k),
  which inflates its 100k totals and the speed-ups against it there; how much
  of it is compilation is not measured.
- **CyteArc pays a first-run cost too.** Its kNN and Leiden compile numba
  kernels on first use. On 10k cells, natively, a second run took 1.5 against
  12.1 s for the kNN step and 0.2 against 13.9 s for Leiden. Each container
  run pays it, as for Scanpy.
- **Defaults that favour Scanpy's speed.** Leiden runs Scanpy's default
  `n_iterations = 2`, and `rank_genes_groups` skips the Wilcoxon tie
  correction by default.
- **tSNE settings are each framework's own.** Iteration counts and learning
  rates are not matched; `sc.tl.tsne` hard-codes `learning_rate = 1000`.
- **UMAP optimisation is single-threaded outside bixverse.** umap-learn under
  Scanpy, uwot under Seurat (`n_sgd_threads = 0`) and scrapper's `runUmap`
  (`parallel.optimization = FALSE`) run the SGD on one thread by default;
  bixverse's default optimiser (`adam_parallel`) uses all 8. CyteArc's
  `embeddings.umap` defaults to `parallel = False` as well. This favours
  bixverse; none of the four is switched to a parallel mode here.
- **Harmony is not one implementation.** Seurat runs the R harmony package
  (with `project.dim = TRUE`), Scanpy harmonypy, scrapper, bixverse and
  CyteArc their own. The same-input comparison covers bixverse and harmonypy only.
- **Per-step times of the lazy rows shift work between steps.** Scanpy Dask,
  scrapper HDF5, BPCells and CyteArc defer computation, so a step can pay for work
  queued earlier. Compare their totals, not single steps.
- **Defaults differ** in scaling, normalisation and graph construction; see
  Workflow.

## Running it

```bash
# PBMC
uv run scripts/subsample.py ~/Desktop/parse_pbmc_1m data/parse_100k 100000
uv run scripts/to_h5ad.py data/parse_100k

# simulation (splatter-sc 0.1.0: cargo install splatter-sc --version 0.1.0).
# The configs in sim/ are committed; they came from these two lines
Rscript scripts/estimate_splat.R data/parse_100k sim/splat_fit.json   # needs splatter
python3 scripts/sim_params.py sim/splat_fit.json 100000 data/splat_100k > sim/splat_100k.json
splatter-sc sim/splat_100k.json   # and splat_10k (smoke test), splat_500k, splat_1m

# images, and the native library for the GPU row
docker build -f docker/r.Dockerfile -t scbench-r .
docker build -f docker/py.Dockerfile -t scbench-py .
docker build -f docker/cytearc.Dockerfile -t scbench-cytearc .
# bixverse, bixverse-rs and manifoldsR sources packed into vendor/ (see the
# header of docker/r-local.Dockerfile)
docker build -f docker/r-local.Dockerfile -t scbench-r:local .
# native library: the same checkouts, bixverse.gpu with the MLX backend (needs mlx-c)
R_LIBS=rlib R CMD INSTALL -l rlib manifoldsR
R_LIBS=rlib R CMD INSTALL -l rlib bixverse
BIXVERSE_GPU_MLX=true R_LIBS=rlib R CMD INSTALL -l rlib bixverse.gpu

# tool: bixverse | scanpy | cytearc | scrapper | seurat_standard | seurat_bpcells
# INPUT: mtx | h5ad | dask (scanpy only) | hdf5 (scrapper only, with TAG=hdf5)
[INPUT=h5ad] [BIX_KNN=nndescent] [BIX_TSNE_KNN=ivf] [TAG=suffix] [STEP_TIMEOUT=2700] [R_IMAGE=scbench-r:local] scripts/run.sh <tool> <dataset>
[BACKEND=mlx] scripts/run_native.sh <dataset>       # bixverse.gpu on Metal: wgpu, or MLX
LOAD_ONLY=1 TAG=disk scripts/run.sh bixverse <dataset>   # on-disk store only

# warm start: reconnect to what the last cold run left in the scratch volume
WARM=1 scripts/run.sh bixverse parse_100k          # or seurat_bpcells

uv run scripts/tables.py results
uv run scripts/score.py results/splat_100k data/splat_100k   # writes quality.csv

# same-input Harmony
uv venv scripts/harmony_bench/.venv && uv pip install --python scripts/harmony_bench/.venv/bin/python harmonypy==2.1.0 pandas
uv run scripts/harmony_bench/prep.py results/harmony_bench
bash scripts/harmony_bench/drive.sh
uv run scripts/harmony_bench/summarise.py stage
uv run scripts/score.py results/harmony_bench/score_splat_100k data/splat_100k   # and score_splat_1m
uv run scripts/harmony_bench/summarise.py report

# figures in docs/figures (ggplot2, patchwork)
uv run scripts/tables.py --long results > docs/figures/results_long.csv
uv run scripts/tables.py --warm results > docs/figures/warm_long.csv
Rscript scripts/plots.R
```
