# Methods

## Setup

- **Machine**: M1 Max, Docker Desktop, containers capped at
  `--cpus=8 --memory=24g`. The VM itself has ~23.4 GB plus ~4 GB swap, and that
  is the limit that actually bites. Slightly stricter than an Air.
- **GPU**: Docker has no Metal access, so the bixverse GPU rows run natively on
  macOS (`scripts/run_native.sh`), on macOS 27.0.1 with R 4.6.1. Two backends
  of bixverse.gpu: wgpu (the GPU row) and MLX (the MLX row). Native runs skip
  the VM, so their I/O and compute are faster than in Docker; the GPU rows are
  therefore compared against the bixverse CPU pipeline run natively too
  (`BACKEND=cpu`, same parameters as the Docker run), in their own tables.
  No memory cap there. Peak memory is the process's peak footprint from
  `/usr/bin/time -l`: dirty anonymous and compressed memory plus the
  process's Metal allocations, but not clean file-backed pages, so like cgroup
  anon it does not charge the mapped bixverse store. It is not the same
  metric as cgroup anon and depends on the R build: the same bixverse.gpu
  0.6.1 tSNE code peaks at 2.0 GB at splat 100k under R 4.5.1 and at 4.2 GB
  rebuilt for R 4.6.1 (same machine and macOS, one run each). The extra is
  CPU heap, not GPU memory.
- **MLX**: experimental, and not what a user gets from a plain install. The
  MLX backend is opt-in at build time: it needs mlx-c installed as a system
  library (`brew install mlx-c`, here mlx-c 0.7.0 against MLX 0.32.3) and
  bixverse.gpu built with `BIXVERSE_GPU_MLX=true`. Apple Silicon only. PCA,
  Harmony, the kNN, the fast clustering's k-means, UMAP and tSNE run on MLX;
  Leiden, DGE and the loaders are the same CPU code as the GPU row.
- **Memory**: cgroup `anon` sampled once a second (`docker/monitor.sh`). Page
  cache is excluded, so streaming tools are not charged for their files. This
  favours the out-of-core rows (bixverse, Seurat BPCells, Scanpy Dask,
  CyteArc): the file pages they read or map do not count, while an
  in-memory row pays for every byte it holds. The cgroup cap counts cached
  pages too and reclaims them under pressure, so it still bounds every run.
  The monitor also logs `shmem` and `file_mapped`, to catch tools that hold
  data in shared memory rather than anon.
- **Cold reads**: every run script (`run.sh`, `run_native.sh`,
  `tahoe/run.sh`, the Harmony driver) empties the macOS file cache with
  `purge` before each run, so every load reads its input from disk. The cache
  that matters sits on the macOS side of the bind mount: dropping the VM's
  page cache did nothing (brisc at 100k loads in 0.7 s warm, 0.7 s after a VM
  drop, 1.6 to 1.9 s after `purge`). `purge` needs root, so it runs through a
  sudoers entry, `<user> ALL=(root) NOPASSWD: /usr/sbin/purge`; `COLD=0`
  skips it.
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
  NNDescent at every size (`BIX_KNN=nndescent`, the harness default). Every
  framework's sNN kNN is approximate (Annoy, hnswlib or NNDescent), so this is
  like for like. The GPU and MLX rows use GPU NNDescent
  (`find_neighbours_gpu_sc`).
- **bixverse-py**: the same Rust through the Python bindings
  (`pipelines/bixverse_pipeline.py`), same steps and parameters as the R
  pipeline, UMAP with `randomised = False` as manifoldsR's default. Its own
  image (`docker/bixverse-py.Dockerfile`, Python 3.12): PyPI only ships
  x86_64 Linux wheels, so bixverse-rs and manifolds-rs are built from source
  for linux/arm64. Against the R rows it runs 2% to 11% faster without tSNE
  (load and DGE, under 3 s at 1M; every other step level). Same Rust, so
  that is the R and Python glue or the build profiles; not investigated.
- **Scanpy Dask**: X read lazily from the h5ad in 50k cell CSR chunks, threaded
  scheduler. `sc.pp.calculate_qc_metrics` peaks at 16.6 GB transiently on 500k
  cells under Dask, whatever the chunk size, and kills the full data set. The
  Dask row therefore computes the three per-cell QC sums with `map_blocks`
  instead (6.2 GB peak, same cells kept). Everything else is stock Scanpy.
  It needs an h5ad; for an MTX-only source the conversion is not timed.
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
- **brisc**: in memory. The whole count matrix is read at load and stays in
  RAM; QC tabulates which cells pass rather than subsetting. Its own Python
  3.12 image (`docker/brisc.Dockerfile`), wheels from PyPI. `num_threads = 8`
  is set at load, as its default `os.cpu_count()` sees the VM's 10 cores, not
  the cap. h5ad only: its MTX reader wants the 10x layout. The simulated h5ad
  stores X chunked, which sends brisc to its fallback reader (forked h5py
  workers into shared buffers) instead of its threaded one; on an unchunked
  copy the warm load at 100k drops from 0.7 to 0.4 s. Since the gzip switch
  every h5ad is chunked, the Parse ones included. All rows read the same
  file, so the harness keeps it.

## Data

**Simulation**: [splatter-sc](https://github.com/GregorLueg/splatter-sc)
v0.1.1, a streaming Rust port of splatter's Splat simulator. It writes the
Parse layout (`DGE.mtx.gz` with `parse_gzip`) and an h5ad, plus the truth
(`cells_truth.tsv.gz`: batch and group per cell; `genes_truth.tsv.gz`: DE
factors per group). The h5ad follows `anndata.write_h5ad(compression="gzip")`
(dtypes, filters, h5py's chunk guess, resizable `X`) except the `X/data` and
`X/indices` chunk length: splatter-sc streams `X` and sizes its chunks from
the expected nonzeros, 0.9% to 2.8% off what h5py picks for the final count.

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
   is a no-op there. No MALAT1 either.

**Parse 1M PBMC**: 987,585 cells, 60,664 genes, 24 samples, plus random 100k
and 500k cell subsamples (`scripts/subsample.py`, seed 42). The mtx rows read
the subsampled mtx; the h5ad rows read `scripts/to_h5ad.py` output. That
conversion runs once, outside the timings, and is in memory; every h5ad row
(bixverse, bixverse-py, Scanpy, Scanpy Dask, scrapper, Seurat, CyteArc,
brisc) is spared it. Only the mtx rows pay for parsing text.

**Compressed inputs**: every data set ships as `DGE.mtx.gz` (gzip level 6,
splatter-sc's default and what `subsample.py` writes) and `DGE.h5ad` (gzip
level 4 without shuffle on every dataset, what `sc.write` and
`write_h5ad(compression="gzip")` give). That's how count matrices sit on most
people's disks, so decompression is part of the load. Before the switch the
inputs were plain `DGE.mtx` and uncompressed h5ads, 80.5 GB for the six data
sets against 20.2 GB now; the counts are identical, checked value by value.
Every Docker row has been rerun on the compressed inputs.

| data set | `DGE.mtx` | `DGE.mtx.gz` | h5ad uncompressed | h5ad gzip |
|---|---|---|---|---|
| splat_100k | 1.43 GB | 0.33 GB | 0.87 GB | 0.28 GB |
| splat_500k | 7.62 GB | 1.68 GB | 4.33 GB | 1.38 GB |
| splat_1m | 15.38 GB | 3.35 GB | 8.67 GB | 2.76 GB |
| parse_100k | 1.57 GB | 0.36 GB | 0.97 GB | 0.28 GB |
| parse_500k | 8.37 GB | 1.81 GB | 4.82 GB | 1.40 GB |
| parse_full | 16.68 GB | 3.58 GB | 9.54 GB | 2.75 GB |

Sizes in 10^9 bytes. Every mtx reader in the stack reads the `.gz` directly
(`Matrix::readMM`, BPCells `import_matrix_market`, `sc.read_mtx`, CyteArc's
`MtxReader`, bixverse from 0.8.4), checked against the plain file on 10k
simulated cells. CyteArc's `inspect_mtx` lists every mtx in the directory, so
its pipeline picks `DGE.mtx.gz` by name.

## Versions

Every row, PBMC and simulation, runs on the same stack.

| framework | versions |
|---|---|
| bixverse | bixverse 0.9.0 (`feat-bixverse-rs-updates` 8a64c261a, bixverse-r crates 0.10.1), manifoldsR 0.6.0 (r-universe) |
| bixverse-py | bixverse 0.3.1 (bixverse-rs `main` 85c6f5a), manifolds-rs 0.6.1 (`main` 9fb0257), Python 3.12 |
| bixverse GPU / MLX (native) | bixverse 0.8.4, bixverse.gpu 0.6.2 (`remove-igraph` b36befe), manifoldsR 0.5.0; not rerun yet |
| Scanpy | 1.12.5 (anndata 0.13.4, dask 2026.8.0, harmonypy 2.1.0, umap-learn 0.5.12, pynndescent 0.7.0, numba 0.68.1, openTSNE 1.0.4, scikit-learn 1.9.1) |
| scrapper | 1.6.3 |
| Seurat | 6.0.0 (SeuratObject 5.4.0, BPCells 0.3.1, harmony 2.0.5, presto 1.1.0, uwot 0.2.5) |
| CyteArc | 1.3.0 (PyPI), Python 3.13 |
| brisc | 0.2.5 (PyPI), Python 3.12, OpenBLAS |

bixverse (R) is built from a `git archive` of the commit in the table
(`docker/r-local.Dockerfile` on top of `scbench-r`, crates from crates.io);
bixverse-py and manifolds-rs from the commits in the table
(`docker/bixverse-py.Dockerfile`). The commits are in `vendor/SHAS`. Scanpy
pins umap-learn 0.5.12: 0.6.0 breaks `sc.pp.neighbors` (numba `TypingError`
on `knn_dists`). The newer pynndescent and numba that come with Scanpy 1.12.5
make its kNN step slower than on the old stack; it is left as installed,
since that is what a user gets. The native GPU and MLX rows still run the
older stack, installed into `rlib/` with the MLX backend, block Lanczos PCA.

## Workflow

Same steps and parameters everywhere, each along the framework's standard
in-memory or out-of-core workflow from its vignettes. Some frameworks
document other routes for large data that are not benchmarked here:
scrapper's batch correction via `block =` plus MNN, Seurat's sketching.

1. **load**: pre-filter as bixverse does it. Genes in at least 5 cells first,
   then cells with at least 100 genes and 250 UMIs. bixverse fuses the
   log-normalisation into this streaming pass, so it has no separate
   normalise step. brisc keeps every gene and cell at load: its QC cuts
   (250 genes, 750 UMIs) cover the cell pre-filter, and the 5-cell gene set
   is counted at load and only used to restrict its markers.
2. **qc**: MT < 5%, total UMIs >= 750, detected genes >= 250. brisc's `qc`
   runs with its MALAT1 filter off (not part of the harness QC) and its MT
   filter off where there are no MT genes, as both raise otherwise. brisc
   finds MT genes by var name, so on PBMC its QC swaps the symbols in (null
   symbols take the Ensembl id, repeats a suffix). Its cut is <= 5% against
   < 5% elsewhere: brisc keeps 0.05% more cells on PBMC full (685,299 against
   684,932), CyteArc 3 more.
3. **normalise**: library size to 1e4 and log1p (bixverse, Scanpy, Seurat);
   centred size factors and log2 (scrapper defaults); CyteArc's default,
   library size to 1000 over the HVGs and log1p, computed lazily, so it runs
   after HVG selection and its cost lands in PCA. brisc's default, log1pPF
   (Ahlmann-Eltze and Huber 2023), after HVG selection, since its HVGs come
   from the raw counts.
4. **hvg**: 2000 genes, each framework's default method. brisc: Seurat v3 on
   raw counts, genes in at least 5 cells, no batch column (as for Scanpy; its
   tutorial passes one for multi-batch data).
5. **pca**: 30 components on the HVGs (scrapper via `runPca(subset =)`, as in
   its vignette). Scanpy and scrapper centre only; Seurat, bixverse and
   CyteArc also scale to unit variance. brisc runs its `pca` at its defaults
   otherwise; whether it scales is not checked.
6. **harmony**: by sample. Scanpy runs harmonypy with `ncores = 8`, the CPU
   cap; Seurat calls `setThreads(8)`, as its threaded kernels (from 5.6.0)
   default to one thread. bixverse runs `harmony_sc`, its v2 Harmony. CyteArc
   runs its own Harmony2 (`reduction.harmony`), brisc its own `harmonize`.
7. **knn_snn**: k = 15. scrapper builds the kNN once (`findKNN` with Annoy)
   and hands it to both `buildSnnGraph` and `runUmap`, as
   `runAllNeighborSteps` in its vignette does; the harness calls the steps one
   by one to keep the per-step times. CyteArc: hnswlib index, k = 15
   neighbours and its fuzzy connectivity graph. brisc: its approximate
   `neighbors` at k = 15 (its default is 20), then `shared_neighbors`.
8. **cluster**: Leiden, resolution 1. The graphs differ, so the cluster counts
   do not compare: Scanpy and CyteArc cluster a UMAP-style fuzzy graph, Seurat and bixverse a
   Jaccard sNN pruned at 1/15 and 1/16, scrapper a rank-weighted sNN
   without pruning, brisc an sNN that keeps pairs sharing at least 3
   neighbours. brisc's default minimum cluster size is 5, so tiny fragments
   survive: at 1M it reports 76 clusters, of which 65 hold 393 cells between
   them.
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
     the totals. CyteArc and brisc have no equivalent.
9. **umap**: defaults. CyteArc's step includes its k-means initialisation
   (`embeddings.initialization`) on the Harmony coordinates, as its recipe does.
   brisc's default optimiser is single-threaded (`hogwild = False`). The
   `brisc h5ad hogwild` column (`BRISC_HOGWILD=1`) switches on its
   multi-threaded Hogwild optimiser, which brisc documents as not
   reproducible between runs. A column of its own, totals included.
10. **dge**: one-vs-rest markers, each framework's default test: bixverse
    `find_all_markers_sc` (Wilcoxon, `min_prop = 0.05`; `find_all_markers`
    in bixverse-py), Scanpy `rank_genes_groups` (Wilcoxon; the t-test on
    Dask, see the caveats), Seurat `FindAllMarkers` (presto),
    scrapper `scoreMarkers` (AUC), CyteArc `markers.search` (Mann-Whitney,
    scored by AUC as for scrapper; genes in at least 5 cells, groups frozen
    from the cell column with `snapshot_cluster_labels`). On BPCells, `FindAllMarkers` does not use
    presto but `BPCells::marker_features` once per group, which wants
    gene-major storage and otherwise warns and transposes on every call. The
    BPCells row therefore transposes the normalised data layer once with
    `transpose_storage_order`, as the warning advises, inside the DGE step:
    its time and its disk copy count against BPCells. It cut DGE from 404 to
    260 s on the 500k simulation and from 1,348 to 1,137 s on the full PBMC
    data, at 0.4 to 1.4 GB more peak memory and three times the disk. brisc's
    `find_markers` is not a test: it scores each gene by its detection rate
    in the group and the fold change of that rate against the rest, with no
    p-values. The harness takes every gene (`all_genes = True`) in at least
    5 cells and ranks on that fold change; a gene detected only in the group
    has an infinite fold change and is set just above the largest finite
    one. Ranking on detection rate instead scored worse at 100k (DGE AUROC
    0.69 against 0.95). On the simulation the groups are
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
    - brisc has no tSNE.

On the simulation the score inputs (clusters, HVGs, embeddings, markers) are
written right after DGE, so a tSNE timeout only loses the tSNE rows.

The warm start (`WARM=1`) times only the reconnect: `load_existing` for
bixverse, `open_matrix_dir` plus `CreateSeuratObject` for Seurat + BPCells,
`DataStore` on the existing store for CyteArc. It needs a cold run of the same
tool and data set first, and lives in `<tool>_warm`. CyteArc's cold run is
load-only (`LOAD_ONLY=1`), since only the store is reopened.

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
- **gzip doesn't split.** Every mtx reader has to inflate one gzip stream, so
  that part of the load runs on one thread whatever the parser does after.
  The h5ad readers inflate chunk by chunk. How much either costs is not
  measured yet.
- **Peak memory includes tSNE.** It is the whole-run peak. For bixverse the
  load sets it (8.1 GB at 1M, h5ad); tSNE stays below.
- **Docker on macOS runs in a VM.** The bixverse CPU pipeline runs 1.3x to
  1.7x faster natively without tSNE, most of it in load (input files reach
  the VM through file sharing). The other frameworks likely pay a similar VM
  tax; only bixverse was run both ways. On a Linux host it should be smaller;
  not measured.
- **The native GPU rows are on the old stack.** bixverse 0.8.4 and
  bixverse.gpu 0.6.2 on uncompressed inputs; they get rerun against the
  current bixverse.
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
- **Cluster counts flip between 11, 12 and 13.** Across rows and reruns with
  the same embedding quality, Leiden returns a different count, and ARI moves
  with it (about 0.87 with 12 clusters against 0.79 with 13 at 1M; 0.98 with
  11 against 0.89 with 12 at 100k). It is not tested across Leiden seeds.
- **Harness code.** The R pre-filter for scrapper and Seurat standard counts
  detections from the sparse slots, but subsetting the matrix still copies
  it; part of their in-memory OOMs may be ours. The Scanpy Dask QC is
  hand-written (see Setup). CyteArc keeps 3 to 5 more PBMC cells than the
  other rows (69,415, 346,264 and 684,935); its QC columns are its own, and
  whether they count genes before or after the 5-cell gene filter is not
  checked. Same cells on the simulation.
- **BPCells DGE includes a transpose.** See Workflow, step 10. Without it
  `FindAllMarkers` on BPCells transposes once per group and is slower; with
  it the step writes a gene-major copy of the data (7.7 GB on the full PBMC
  data). The split between transpose and marker test is not timed.
- **Two DGE steps are not Wilcoxon.** Scanpy Dask runs the t-test: Wilcoxon
  `rank_genes_groups` fails on Dask arrays in Scanpy 1.12.5 (numba
  `TypingError` in `_ranks`), and the t-test is the only method that works
  there. brisc ranks by detection rate and fold change in detection rate with
  no test at all, so its 0.0 to 0.3 s DGE step does not compare with the
  others. On detectable markers the t-test holds up (R-precision 0.93 on the
  500k simulation, in line with the Wilcoxon rows); brisc's ranking does not
  (0.29 at 100k and 0.34 at 1M, against 0.88 to 0.94 for the rest). Both are
  marked * in the step heatmaps. The t-test also pushes the Dask row to the
  24 GB cap at 1M cells: it OOMs in DGE on the 1M simulation and peaks at
  24.0 GB on PBMC full.
- **`cluster_fast` on the CPU is slower than the Leiden it replaces** from
  500k (bixverse 15 against 3 s at 500k, 47 against 6 s at 1M; scrapper 192
  against 114 s). It is in the tables as an option, not in the totals.
- **scrapper survives 500k on swap.** Both scrapper rows reach the 24 GB cap
  at 500k (PBMC and simulation) and finish by swapping, so their 500k times
  include swap traffic. In the earlier run on the plain `DGE.mtx` the PBMC
  500k mtx row died at load; whether the gzip read is what saves it now is
  not tested.
- **No scrapper HDF5 row.** scrapper on an `HDF5Array::H5ADMatrix` ran in
  earlier versions of this benchmark. On the gzip h5ad it went from 4 to
  15 min at 100k and timed out in DGE at 1M, so it was dropped.
- **No OSCA row.** The Bioconductor stack (scuttle, scran, scater) on the
  same HDF5-backed matrix does not finish HVG at any size from 500k up within
  45 min, and its forked workers OOM at 100k in PCA and DGE. Its row-wise
  kernels (`modelGeneVar`, `scoreMarkers`) see a delayed, non-pristine matrix
  after `logNormCounts`, so beachmat falls back to R-level block processing,
  and HDF5Array's CSC extractor loads every column for each row block of the
  cell-major file. scran 1.40 and scuttle 1.22 deprecate these functions in
  favour of scrapper.
- **Scanpy pays a first-run cost.** Each run is a fresh container, so numba
  compiles its kernels every time; the numba cache is partial and lost with
  the container. This is what a user running the pipeline once sees, and it
  is left in. Scanpy's kNN shows a fixed cost (27 s at 100k, 33 s at 500k),
  which inflates its 100k totals and the speed-ups against it there; how much
  of it is compilation is not measured.
- **CyteArc pays a first-run cost too.** Its kNN and Leiden compile numba
  kernels on first use, and each container run pays it, as for Scanpy.
- **Defaults that favour Scanpy's speed.** Leiden runs Scanpy's default
  `n_iterations = 2`, and `rank_genes_groups` skips the Wilcoxon tie
  correction by default.
- **tSNE settings are each framework's own.** Iteration counts and learning
  rates are not matched; `sc.tl.tsne` hard-codes `learning_rate = 1000`.
- **UMAP settings are each framework's own.** Epochs, optimiser and graph
  weights are not matched.
- **UMAP optimisation is single-threaded outside bixverse.** umap-learn under
  Scanpy, uwot under Seurat (`n_sgd_threads = 0`) and scrapper's `runUmap`
  (`parallel.optimization = FALSE`) run the SGD on one thread by default;
  bixverse's default optimiser (`adam_parallel`) uses all 8. CyteArc's
  `embeddings.umap` and brisc's `umap` default to one thread as well. This
  favours bixverse. Only brisc gets an extra parallel column (Hogwild); at
  100k it cut UMAP from 27.2 to 5.6 s and at 1M from 278 to 64 s (one run
  each). The other four stay on one thread.
- **Harmony is not one implementation.** Seurat runs the R harmony package
  (with `project.dim = TRUE`), Scanpy harmonypy, scrapper, bixverse,
  CyteArc and brisc their own. The same-input comparison covers bixverse and harmonypy only.
- **Per-step times of the lazy rows shift work between steps.** Scanpy Dask,
  BPCells and CyteArc defer computation, so a step can pay for work
  queued earlier. Compare their totals, not single steps.
- **brisc runs on OpenBLAS.** MKL is x86-only and Accelerate macOS-only, so
  linux/arm64 gets OpenBLAS, which brisc's docs call slower. This works
  against brisc; by how much is not measured.
- **brisc's anon peak runs short.** At 1M its max RSS (12.3 GiB) sits about
  4 GB above the cgroup anon peak (8.1 GB); `shmem` and `file_mapped` do not
  account for the gap. At 100k: 1.4 GiB against 0.7 GB.
- **Defaults differ** in scaling, normalisation and graph construction; see
  Workflow.

## Running it

```bash
# PBMC
uv run scripts/subsample.py ~/Desktop/parse_pbmc_1m data/parse_100k 100000
uv run scripts/to_h5ad.py data/parse_100k

# simulation (splatter-sc 0.1.1: cargo install splatter-sc --version 0.1.1).
# The configs in sim/ are committed; they came from these two lines
Rscript scripts/estimate_splat.R data/parse_100k sim/splat_fit.json   # needs splatter
python3 scripts/sim_params.py sim/splat_fit.json 100000 data/splat_100k > sim/splat_100k.json
splatter-sc sim/splat_100k.json   # and splat_10k (smoke test), splat_500k, splat_1m

# images, and the native library for the GPU row
docker build -f docker/r.Dockerfile -t scbench-r .
docker build -f docker/py.Dockerfile -t scbench-py .
docker build -f docker/cytearc.Dockerfile -t scbench-cytearc .
docker build -f docker/brisc.Dockerfile -t scbench-brisc .
docker build -f docker/bixverse-py.Dockerfile -t scbench-bixverse-py .
# bixverse and manifoldsR sources packed into vendor/ (see the
# header of docker/r-local.Dockerfile)
docker build -f docker/r-local.Dockerfile -t scbench-r:local .
# native library: the same checkouts, bixverse.gpu with the MLX backend (needs mlx-c)
R_LIBS=rlib R CMD INSTALL -l rlib manifoldsR
R_LIBS=rlib R CMD INSTALL -l rlib bixverse
BIXVERSE_GPU_MLX=true R_LIBS=rlib R CMD INSTALL -l rlib bixverse.gpu

# cold reads: every run script calls `sudo -n /usr/sbin/purge` first (COLD=0 skips it).
# Once, in a real terminal:  sudo visudo -f /etc/sudoers.d/purge
#   and add:                 <user> ALL=(root) NOPASSWD: /usr/sbin/purge

# tool: bixverse | bixverse_py | scanpy | cytearc | brisc | scrapper | seurat_standard | seurat_bpcells
# INPUT: mtx | h5ad | dask (scanpy only); brisc h5ad only. DGE_METHOD overrides Scanpy's test
[COLD=0] [INPUT=h5ad] [BIX_KNN=nndescent] [BIX_TSNE_KNN=ivf] [TAG=suffix] [STEP_TIMEOUT=2700] [R_IMAGE=scbench-r:local] scripts/run.sh <tool> <dataset>
[BACKEND=mlx] scripts/run_native.sh <dataset>       # bixverse.gpu on Metal: wgpu, or MLX
BACKEND=cpu BIX_KNN=nndescent [BIX_TSNE_KNN=ivf] scripts/run_native.sh <dataset>   # native CPU control
LOAD_ONLY=1 TAG=disk scripts/run.sh bixverse <dataset>   # on-disk store only
INPUT=h5ad TAG=h5ad scripts/run.sh brisc <dataset>
BRISC_HOGWILD=1 INPUT=h5ad TAG=h5ad_hogwild scripts/run.sh brisc <dataset>   # multi-threaded UMAP

# warm start: reconnect to what the last cold run left in the scratch volume
WARM=1 scripts/run.sh bixverse parse_100k          # or seurat_bpcells, cytearc

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
