# Tahoe-100M out-of-core benchmark: handover

State as of 2026-10-29. bixverse 0.8.4 done on plate 3 and on two plates
(CPU in Docker, MLX native). Scanpy Dask, CyteArc and Seurat BPCells have only
the plate 3 pilot; their two-plate runs go one per overnight window.

## Setup

- Harness: `tahoe/run.sh <tool>` (Docker), tools
  `bixverse | seurat_bpcells | scanpy_dask | cytearc`; `tahoe/run_native.sh`
  for bixverse.gpu (default MLX). Pipelines in `tahoe/pipelines/`.
- Data: `~/Desktop/tahoe100m_h5ad/` (plate1 5.48M cells, plate3 4.71M, plus
  `obs_metadata.parquet`). `pilot/` holds a hard link to plate3 only.
- Two plates: `DATASET=tahoe tahoe/run.sh <tool>`. Single plate:
  `DATA=~/Desktop/tahoe100m_h5ad/pilot DATASET=tahoe_pilot MIN_CELLS=4000 BATCH_COL=sublibrary tahoe/run.sh <tool>`
  (plate is constant on one plate).
- bixverse PCA solver: `PCA_SOLVER=auto|covariance` (default `auto`).
- Docker on/off without prompts: `osascript -e 'quit app "Docker Desktop"'`,
  `open -a "Docker Desktop"` (allowed in `.claude/settings.local.json` of the
  main checkout). Quit Docker before native runs: the VM keeps about 21 GiB.
- Outputs per run in `tahoe/results/<dataset>/<tool>[_TAG]/`, untracked.
  Native `mem.csv` adds system swap above start (`swap_bytes`) and `swapouts`.
- Scoring: `uv run tahoe/score.py tahoe/results/<dataset>`.

## Decisions (Gregor's)

- Steps: load, QC, HVG, PCA, Harmony, kNN/sNN, UMAP, DGE. No Leiden, no tSNE.
  UMAP and PCA at defaults for the reported rows.
- QC: MT <= 15%, UMI >= 750, genes >= 250. Gene cut: detected in >= 9,000
  cells (`MIN_CELLS`, about 0.1%), all four tools; 4,000 on one plate.
- Harmony on `plate`: the only batch with an effect on identical cells (DMSO,
  neighbour enrichment 1.17x; sublibrary 1.03 to 1.21x). Plate is confounded
  with dose (plate1 every drug at 0.05 uM, plate3 at 5 uM; only DMSO_TF and
  Adagrasib 0.05 uM on both). Harmony converges at iteration 1. Score batch
  mixing on DMSO cells only.
- Truth `cell_line`; DGE Gemcitabine vs DMSO_TF.
- 5 h wall, Docker cap 48 GB, stores deleted after each run. Docker disk 200 GB.
- bixverse `BIX_CSC_GB` 8 in Docker, 24 natively (see findings).
- Versions: bixverse 0.8.4 (`scbench-r:local`), bixverse.gpu 0.6.2 from the
  site library for native runs (`rlib/` is stale: 0.5.5 / 0.3.4), CyteArc
  1.3.0, `scbench-py`. The plate 3 bixverse row from 0.8.0 is obsolete.

## Results

Seconds / step peak GiB (Docker: cgroup anon; native: RSS incl. file-backed
pages, footprint from `/usr/bin/time -l`).

Plate 3 (4.02M cells after QC). Other tools from the pilot (5-cell gene cut,
Harmony on sublibrary); bixverse CPU likewise; MLX with the 4k gene cut and
24 GB CSC, native.

| step | bixverse CPU | bixverse MLX | Scanpy Dask | Seurat BPCells | CyteArc |
|---|---|---|---|---|---|
| load | 166.1 / 8.7 | 121.9 | 867.2 / 8.4 | 1,156.3 / 3.9 | 826.4 / 17.0 |
| qc | 23.9 / 2.2 | 16.0 | 145.0 / 5.6 | 56.4 / 4.7 | 0.5 / 0.0 |
| normalise | in load | in load | 0.0 | 25.9 / 5.2 | 147.2 / 3.9 |
| hvg | 10.8 / 3.6 | 8.0 | 145.9 / 10.4 | 142.2 / 5.7 | 134.5 / 3.7 |
| pca | 48.1 / 18.8 | 9.2 | 284.7 / 16.9 | 3,087.0 / 8.0 | 225.1 / 3.5 |
| harmony | 9.4 / 11.7 | 5.2 | 11.0 / 7.5 | 254.8 / 16.4 | 369.0 / 8.1 |
| knn_snn | 105.6 / 15.6 | 33.2 | 109.5 / 13.8 | 512.8 / 18.4 | 1,426.9 / 4.3 |
| umap | 449.7 / 20.7 | 94.3 | 2,276.9 / 14.4 | 3,876.7 / 36.5 | 4,126.8 / 7.1 |
| dge | 9.9 / 11.8 | 4.9 | 354.3 / 20.2 | 51.6 / 31.7 | 118.7 / 4.5 |
| total | 823.5 / 20.7 | 292.7 / 28.9 footprint | 4,194.5 / 20.2 | 9,163.6 / 36.5 | 7,375.1 / 17.0 |
| store GB | 12.9 | 12.4 | 0 | 10.3 | 38.4 |

Two plates (9.21M cells after QC, 9k gene cut, Harmony on plate):

| step | CPU `auto` (feasibility: 5-cell cut) | CPU `auto` (x2) | CPU `covariance` | MLX native |
|---|---|---|---|---|
| load | 940.9 / 9.7 | 833.3, 870.0 | 837.1 / 10.1 | 300.7 |
| qc | 56.2 / 3.8 | 49.3, 53.4 | 54.6 / 3.9 | 29.1 |
| hvg | 27.2 / 5.7 | 28.0, 28.0 | 28.6 / 8.1 | 15.8 |
| pca | 172.6 / 47.0 | **OOM** both, 47.6 + 3.5 to 3.7 swap | 129.9 / 31.7 | 26.4 |
| harmony | 27.6 / 24.6 | - | 33.7 / 25.6 | 10.2 |
| knn_snn | 288.8 / 36.2 | - | 301.6 / 35.8 | 90.5 |
| umap | 1,212.1 / 41.6 | - | 1,140.3 / 42.6 | 302.0 |
| dge | 37.7 / 31.8 | - | 35.4 / 31.4 | 15.1 |
| total | 2,763.1 / 47.0 | failed | 2,561.4 / 42.6 | 789.8 / 57.2 footprint |
| store GB | 33.6 | - | 30.9 | 30.9 |

Result dirs: `tahoe/results/tahoe/bixverse_feasibility`, `bixverse` and
`bixverse_auto_retry` (the OOMs), `bixverse_covariance`, `bixverse_mlx`.
Default `auto` PCA survived 1 of 3 two-plate runs at the 48 GB cap. Framing
agreed with Gregor: default row is the headline, covariance a labelled row
("one documented option, exact"), and the methods say the other tools ran at
defaults without exploring their own options.

PCA solver check, plate 3, one session (4k gene cut): `auto` 59.1 s, about
20 GiB own; `covariance` 41.3 s, about 10 GiB; |cor| 1.000000 on all 30 PCs,
max subspace angle 0.0000 deg.

## Next

1. Scanpy Dask and CyteArc two-plate (one night), Seurat BPCells (the next).
   Projections from the pilot at 2.5x (unmeasured): Scanpy about 10,500 s
   with a DGE peak near the cap (its DGE groups grow 3.1x); Seurat about
   22,900 s, over the 5 h wall, and peaks well over 48 GB; CyteArc about
   18,400 s, at the wall.
2. Rerun the bixverse rows after Gregor's fixes (Lanczos copies, spectral
   init). The "reduce-lanczos-svd-memory" session works on the Lanczos path.
3. Scoring: fix `write_embs` (one shared barcode list from the parquet across
   tools; cell id formats differ: bixverse `plate1_BC`, CyteArc `plate1__BC`),
   score batch mixing on DMSO cells only, then `tahoe/score.py`.
4. Optional, queued by nothing: PCA solver sweep across sizes (for an `auto`
   switch to covariance) and UMAP init spectral vs PCA (time, peak, purity) on
   PBMC full and splat 1M, natively, about 30 min in all.

## bixverse findings (for bixverse-rs; ask Gregor which copy)

- PCA (sparse Lanczos) holds about 32 B per HVG non-zero: CSC + transposed CSR
  + two f64 copies (`bixverse-core/src/core/math/sparse.rs:1827-1860`). The
  sparse covariance solver halves it but still holds the full CSR; a
  streaming Gram over cell chunks would take it to a few GB (CyteArc's design,
  `cytearc/embeddings/reduction.py:207-257`).
- UMAP spectral init is the peak of the MLX two-plate run: about +22 to 25
  GiB over the kNN base for 40 s. The MLX optimisation sits at about +12 GiB.
  macOS swapped out 11,451 pages right after UMAP while the R process was at
  18 GiB: memory outside RSS (Metal buffers or the compressor), not attributed.
- `adam_parallel` forces 500 UMAP epochs at any size (umap-learn uses 200
  above 10k cells); optimisation is edges x epochs.
- CSC conversion in Docker: `BIX_CSC_GB` 24 is 2x slower than 8 on plate 3
  (83.2 against 42.6 s) and 5x slower than 24 natively (22.9 s). During the
  scatter anon is at 23.6 GiB and page cache at 19 to 21.5 GiB, about 45 of
  48 GB: likely page cache eviction under the cgroup cap (inferred). Deriving
  the budget from the cgroup limit would avoid it.
- Load scales worse than linear on two plates (5.7x for 2.5x the non-zeros),
  mostly the 14-phase CSC conversion; untested whether the multi-file path or
  the phase count is the cause.
- `prescan_h5ad_files` does not follow the `/var` `_index` attribute
  (`var_index` defaults to `"_index"`; Tahoe names it `gene_name`), while
  `load_h5ad` copes. The pipelines pass it explicitly.

## Open issues to explain or disclose

- Scanpy purity 0.08 below the rest on plate 3 (cause unknown).
- CyteArc fold changes sit slightly low against bixverse and Scanpy.
- bixverse LFC is about half the others' (different definition; reports only
  genes in >= 5% of a group).
- Cells after QC differ by up to 76 between tools on plate 3; MLX and CPU
  bixverse agree on two plates (9,208,836).
- CyteArc QC takes 0.5 s (likely lazy). Scanpy DGE materialises the two groups.

## Docs out of date (remind Gregor, do not edit unasked)

README and `docs/methods.md`: Tahoe not described at all. To disclose: MT 15%,
the 9k gene cut, Harmony on plate and its dose confound, `BIX_CSC_GB` 8 in
Docker and why, BPCells uint32 conversion, Scanpy in-memory DGE, the 5 h wall,
the covariance row and the OOM count of the default.
