# Methods

## Setup

- **Machine**: M1 Max, Docker Desktop, containers capped at
  `--cpus=8 --memory=24g`. The VM itself has ~23.4 GB plus ~4 GB swap, and that
  is the limit that actually bites. Slightly stricter than an Air.
- **GPU**: Docker has no Metal access, so the bixverse GPU row runs natively on
  macOS (`scripts/run_native.sh`). No memory cap there, and its peak is process
  RSS including resident memory-mapped files. Not comparable to the Docker
  numbers, and its disk I/O skips the VM, so its load is faster too.
- **Memory**: cgroup `anon` sampled once a second (`docker/monitor.sh`). Page
  cache is excluded, so streaming tools are not charged for their files.
- **Disk**: `run.sh` records what a run leaves in its scratch volume
  (`scratch_kb`): the bixverse store and the BPCells matrix dirs. Input files
  are not counted. Measuring right after load (`LOAD_ONLY=1`) gives the same
  size as after a full run (BPCells on 1M simulated cells: 3,747 against
  3,748 MB).
- **Watchdog**: a run is killed when no step finishes for `STEP_TIMEOUT`
  seconds (30 min by default). The tables mark it as **TIMEOUT**.
- **Repeats**: one per run. Treat differences of a few seconds as noise.
- **bixverse**: loaders use `csc_mem_gb = 8` as in the big data vignette; the
  sNN kNN is nndescent (`BIX_KNN=nndescent`). The GPU row uses GPU NNDescent
  (`find_neighbours_gpu_sc`). Older bixverse results live in
  `results/archive_bixverse_*`.
- **Scanpy Dask**: X read lazily from the h5ad in 50k cell CSR chunks, threaded
  scheduler. `sc.pp.calculate_qc_metrics` peaks at 16.6 GB transiently on 500k
  cells under Dask, whatever the chunk size, and kills the full data set. The
  Dask row therefore computes the three per-cell QC sums with `map_blocks`
  instead (6.2 GB peak, same cells kept). Everything else is stock Scanpy.
- **OSCA HDF5**: SingleCellExperiment over `HDF5Array::H5ADMatrix`, the
  documented Bioconductor path with `MulticoreParam(8)`. It does not survive
  HVG at 500k on PBMC, nor PCA at 100k on the simulation; see the caveats.

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
the Parse mtx; the h5ad rows read `scripts/to_h5ad.py` output.

## Versions

The PBMC tables ran on the older stack; the simulation ran on the current one.

| framework | PBMC runs | simulation runs |
|---|---|---|
| bixverse | 0.5.5 (bixverse-rs 0.5.7), bixverse.gpu 0.3.4, manifoldsR 0.3.6, from r-universe | 0.6.0 (bixverse-rs 0.6.0), bixverse.gpu 0.3.6, manifoldsR 0.3.7 |
| Scanpy | 1.12.4 (anndata 0.13.4, dask 2026.8.0, harmonypy 2.0.2, openTSNE 1.0.4, scikit-learn 1.9.1) | the same, with harmonypy 2.1.0 |
| scrapper | 1.6.3 | 1.6.3 |
| Seurat | 5.5.1 (BPCells 0.3.1, harmony 2.0.5) | 5.6.0 (SeuratObject 5.4.0, BPCells 0.3.1, harmony 2.0.5, presto 1.1.0, uwot 0.2.5) |
| OSCA | scran 1.40.0, scater 1.40.2, scuttle 1.22.0, HDF5Array 1.40.0, BiocSingular 1.28.0, bluster 1.22.0 | the same |

TODO, before this goes public:

- **bixverse 0.6.0** is a local build: the `feat-archive` working tree,
  bixverse-rs from the `release-0.6.0` branch on GitHub (`23530c4`), via
  `docker/r-local.Dockerfile`. One local patch: `verbose = 0` added to the
  `cellphonedb_statistical` call in `r_sc_analysis.rs`, until the CellPhoneDB
  verbosity is wired through. Switch to the r-universe release once it is out.
- **bixverse.gpu** is the local `feat-fast-mnn` working tree, installed into
  `rlib/`. r-universe has an older 0.3.6.
- **PBMC tables** still run on the old stack (above), with no DGE step. Rerun
  them on the released versions.

Released and pinned: harmonypy 2.1.0 (PyPI), manifoldsR 0.3.7 (r-universe),
Seurat 5.6.0 (CRAN), splatter-sc 0.1.0 (crates.io). The harmonypy rows ran on
commit `6994444`, which is 2.1.0 minus the version bump.

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
6. **harmony**: by sample. Scanpy runs harmonypy with `ncores = 8`, the CPU
   cap; Seurat calls `setThreads(8)`, as its 5.6.0 kernels default to one
   thread.
7. **knn_snn**: k = 15.
8. **cluster**: Leiden, resolution 1. The graphs differ, so the cluster counts
   do not compare: Scanpy clusters the UMAP fuzzy graph, Seurat and bixverse a
   Jaccard sNN pruned at 1/15 and 1/12, scrapper and OSCA a rank-weighted sNN
   without pruning.
9. **umap**: defaults.
10. **dge**: one-vs-rest markers, each framework's default test: bixverse
    `find_all_markers_sc` (Wilcoxon, `min_prop = 0.05`), Scanpy
    `rank_genes_groups` (Wilcoxon), Seurat `FindAllMarkers` (presto),
    scrapper and OSCA `scoreMarkers` (AUC). On the simulation the groups are
    the true ones, so this tests the DE engine rather than the clustering. On
    PBMC they are the 24 samples, the same workload for everyone.
11. **tsne**: perplexity 30, each tSNE builds its own kNN at k = 3 x
    perplexity.
    - `tsne_default`: each framework's standard Barnes-Hut.
    - `tsne_fft`: FFT where it exists (bixverse `fft_3k`, `fft_3k_gpu` on the
      GPU, Seurat's FIt-SNE, openTSNE for Scanpy).
    - `tsne_quick (qd)`: the quick-and-dirty Barnes-Hut of qdtsne (depth-capped
      tree, repulsion per leaf) at scrapper's defaults: theta 1, 500
      iterations, 250 early exaggeration at 12, max depth 7. scrapper and
      bixverse (`manifoldsR::tsne(approx_type = "bh_qd")`, and `"bh_qd"` on
      the GPU). Not a standard tSNE.

On the simulation the score inputs (clusters, HVGs, embeddings, markers) are
written right after DGE, so a tSNE timeout only loses the tSNE rows.

The warm start (`WARM=1`) times only the reconnect: `load_existing` for
bixverse, `open_matrix_dir` plus `CreateSeuratObject` for Seurat + BPCells. It
needs a cold run of the same tool and data set first, and lives in
`<tool>_warm`.

Inside tSNE the bixverse CPU runs use kmknn at 100k and IVF (default `n_list`,
`n_probes`) from 500k up (`BIX_TSNE_KNN=ivf`). kmknn takes 1.7 s at 100k but
49 s at 500k and 182 s on the full PBMC data. For UMAP, bixverse and Scanpy
reuse the graph; Seurat, scrapper and OSCA rebuild it.

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
the same input, bixverse 0.6.0's 30 PC PCA of the 100k and 1M simulations plus
the true batch labels. Each run is its own process, 8 threads (Rayon for
bixverse, `ncores = 8` for harmonypy), native, 3 repeats. The time covers the
Harmony call only; extra memory is the peak RSS over a load-only run.
bixverse v1 (`rs_harmony`), v2 (`rs_harmony_v2`) and the GPU path
(`rs_harmony_v2_gpu`) are called with the same preprocessing as their
wrappers. Defaults throughout; v2 at harmonypy's `block_size = 0.05` is a
matched extra. The outputs go through `score.py` and a kNN overlap against
harmonypy.

## Caveats

- **One repeat, one machine, one simulation seed.** Apple Silicon under
  Docker, not a real 24 GB laptop.
- **Splat is the easy case.** No gene-gene structure beyond the DE, no
  continuous states, convex groups of similar density, and a multiplicative
  batch effect on every gene. The quality scores rank pipelines on that, not
  on real data.
- **Uncorrected batch mixing is not a quality score.** HVG selectors that
  keep well-expressed genes (scrapper, OSCA) see more of Splat's per-gene
  batch effect, as well as more of the group signal.
- **bixverse over-splits.** Its Jaccard sNN pruned at 1/12 keeps about 4% of
  the full sNN edges at 100k, and Leiden then splits true groups (13 clusters
  for 12 groups at 100k, ARI about 0.79). 0.6.0 re-attaches the isolated
  islands the pruning left (1,048 clusters down to 44 to 48 at 1M), but tight
  cliques of up to 10 cells still come out as their own Leiden communities.
- **Harness code.** The R pre-filter for scrapper and Seurat standard makes
  copies (`counts > 0`, column subsetting); part of their in-memory OOMs may
  be ours. The Scanpy Dask QC is hand-written (see Setup).
- **No DGE for Scanpy Dask.** Wilcoxon `rank_genes_groups` fails on Dask
  arrays in Scanpy 1.12.4 (numba `TypingError` in `_select_top_n`). Only the
  t-test runs, and a t-test on zero-inflated counts is not a like-for-like
  substitute, so the Dask row has no DGE step.
- **OSCA: OOMs in parallel, impractical serially.** The documented path
  (`MulticoreParam(8)`) takes 609 s for HVG at 100k PBMC at 22.7 GB plus 3.7 GB
  swap; at 500k and on the full data the kernel kills a forked worker there.
  On the 100k simulation it finishes HVG serially (365 s) and a PCA worker is
  killed instead. Two follow-ups at 100k PBMC, on a machine shared with other
  tests:
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
  tried here. The same logs mark `perCellQCMetrics`, `librarySizeFactors` and
  `normalizeCounts` as deprecated in favour of scrapper.
- **Defaults differ** in scaling, normalisation and graph construction; see
  Workflow.

## Running it

```bash
# PBMC
uv run scripts/subsample.py ~/Desktop/parse_pbmc_1m data/parse_100k 100000
uv run scripts/to_h5ad.py data/parse_100k

# simulation (splatter-sc 0.1.0: cargo install splatter-sc --version 0.1.0)
Rscript scripts/estimate_splat.R data/parse_100k sim/splat_fit.json   # needs splatter
python3 scripts/sim_params.py sim/splat_fit.json 100000 data/splat_100k > sim/splat_100k.json
splatter-sc sim/splat_100k.json

# images, and the native library for the GPU row
docker build -f docker/r.Dockerfile -t scbench-r .
docker build -f docker/py.Dockerfile -t scbench-py .
R_LIBS=rlib Rscript -e 'install.packages(c("manifoldsR", "bixverse", "bixverse.gpu"), lib = "rlib", repos = c("https://gregorlueg.r-universe.dev", "https://cloud.r-project.org"))'
# TODO: bixverse 0.6.0 from a local checkout until it is released, see docker/r-local.Dockerfile

# tool: bixverse | scanpy | scrapper | seurat_standard | seurat_bpcells | osca
# INPUT: mtx | h5ad | dask (scanpy only)
[INPUT=h5ad] [BIX_KNN=nndescent] [BIX_TSNE_KNN=ivf] [TAG=suffix] [STEP_TIMEOUT=1800] [R_IMAGE=scbench-r:local] scripts/run.sh <tool> <dataset>
scripts/run_native.sh <dataset>       # bixverse.gpu on Metal
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

# figures in docs/figures (ggplot2, patchwork, ggrepel)
uv run scripts/tables.py --long results > docs/figures/results_long.csv
uv run scripts/tables.py --warm results > docs/figures/warm_long.csv
Rscript scripts/plots.R
```
