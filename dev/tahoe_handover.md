# Tahoe-100M out-of-core benchmark: handover

State as of 2026-10-28. Plate 3 pilot done for all four tools and scored. The
two-plate run (plates 1 and 3) is on hold until Gregor says go.

## Setup

- Harness: `tahoe/run.sh <tool>`, tools `bixverse | seurat_bpcells | scanpy_dask | cytearc`.
  Pipelines in `tahoe/pipelines/`, mounted at `/bench/pipelines`. The PBMC/sim
  harness (`scripts/run.sh`, `pipelines/`) is separate and untouched.
- Data: `~/Desktop/tahoe100m_h5ad/` (plate1 5.48M cells, plate3 4.71M, plus
  `obs_metadata.parquet`). `pilot/` holds a hard link to plate3 only.
- Pilot command:
  `DATA=~/Desktop/tahoe100m_h5ad/pilot DATASET=tahoe_pilot tahoe/run.sh <tool>`.
  bixverse also ran with `BIX_CSC_GB=32 TAG=csc32`.
- Scoring: `uv run tahoe/score.py tahoe/results/<dataset>`, writes
  `quality.csv` and `dge_agreement.csv`.
- Outputs per run in `tahoe/results/<dataset>/<tool>/`: `log.txt`,
  `steps.csv`, `mem.csv` (anon bytes sampled), `scratch_kb` (store size before
  deletion), embeddings, `score_cells.csv.gz`, `markers.csv`. Untracked.

## Decisions (Gregor's, do not revisit)

- Native multi-file ingest per tool. Steps: load, QC, HVG, PCA, Harmony,
  kNN/sNN, UMAP, DGE. No Leiden, no tSNE, no cluster_fast.
- QC: MT <= 15% (deviation from the PBMC 5%), UMI >= 750, genes >= 250.
- Harmony on `sublibrary`; truth `cell_line`; DGE Gemcitabine vs DMSO_TF.
- 5 h wall per run, Docker cap 48 GB, stores deleted after each run.
- Versions unchanged: `scbench-r:local`, CyteArc 1.3.0, `scbench-py`.
- bixverse at `BIX_CSC_GB` 8 is the main row; 32 gave no net gain.

## Pilot results (plate 3, 4.02M cells after QC)

| step | bixverse 8 GB | Scanpy Dask | Seurat BPCells | CyteArc |
|---|---|---|---|---|
| load | 1212 s / 12.3 GB | 867 / 9.0 | 1156 / 4.2 | 826 / 18.3 |
| qc | 96 / 4.7 | 145 / 6.0 | 56 / 5.1 | 0.5 / 0.0 |
| normalise | in load | 0 / 0 | 26 / 5.6 | 147 / 4.2 |
| hvg | 188 / 6.6 | 146 / 11.1 | 142 / 6.1 | 135 / 3.9 |
| pca | 41 / 12.8 | 285 / 18.1 | 3087 / 8.6 | 225 / 3.8 |
| harmony | 11 / 11.3 | 11 / 8.1 | 255 / 17.6 | 369 / 8.7 |
| knn_snn | 194 / 24.5 | 110 / 14.8 | 513 / 19.8 | 1427 / 4.6 |
| umap | 440 / 34.9 | 2277 / 15.4 | 3877 / 39.2 | 4127 / 7.6 |
| dge | 13 / 25.2 | 354 / 21.7 | 52 / 34.0 | 119 / 4.9 |
| total | 2193 / 34.9 | 4195 / 21.7 | 9164 / 39.2 | 7375 / 18.3 |
| store | 67.3 GB | 0 | 10.8 GB | 40.3 GB |

Peak GB is container anon memory within the step, so it includes whatever
earlier steps left resident.

Scores (50k cells per tool, K = 15): Harmony kNN purity on cell_line 0.904
bixverse, 0.827 Scanpy, 0.907 Seurat, 0.914 CyteArc. Batch mixing about 1.0
for all. DGE log fold change Spearman between tools 0.86 to 1.00.

## Open issues, harness (fix before the two-plate run)

1. `write_embs` (`tahoe/pipelines/common.R`, `common.py`) samples 200k cells
   independently per tool, so tools share almost no scored cells. Draw one
   barcode list from the parquet and have every tool write those cells. Cell
   id formats differ (bixverse `plate1_BC`, CyteArc `plate1__BC`, single plate
   unprefixed for bixverse and CyteArc).
2. Batch mixing is about 1.0 everywhere, so it does not discriminate. Save an
   uncorrected PCA embedding and score it to see whether sublibrary carries a
   batch effect at all.
3. Docker disk: the bixverse store took 67 GB on one plate; raise Docker's
   disk image before two plates.
4. Seurat may exceed the 5 h wall and 48 GB on two plates (projection from
   the pilot, unmeasured).

## Open issues, to explain or disclose (no fix yet)

- Scanpy purity 0.08 below the rest. Cause unknown (harmonypy, HVG flavour?).
- CyteArc fold changes sit slightly low: 644 genes where bixverse has a tiny
  positive LFC (< 0.05) and CyteArc negative; bixverse and Scanpy agree on all.
  Points at CyteArc's normalisation or averaging.
- bixverse LFC is about half the others' (MT-ND1 -0.63 vs Scanpy -1.49),
  probably a different definition; it only reports genes in >= 5% of a group
  (7,086 genes).
- Cells after QC differ by up to 76 between tools (bixverse 4,022,932,
  Scanpy/Seurat 4,023,005, CyteArc 4,023,008). Unexplained.
- CyteArc QC takes 0.5 s: likely lazy, the cost lands in later steps.
- Scanpy DGE materialises the two groups in memory (Wilcoxon fails on Dask).
- `sessionInfo` in `scbench-r:local` says bixverse 0.8.0, README says 0.8.1.

## bixverse findings (fixes go in the bixverse repo; ask Gregor which copy)

From `tahoe/results/tahoe_pilot/bixverse/log.txt` and `mem.csv`:

- kNN/sNN 193.7 s: NNDescent 88.8 s, extract 0.2 s, sNN build 22.0 s, about
  83 s unlogged (Rust -> R -> igraph transfer). Memory 6.4 -> 24.5 GB and
  still 24.5 GB after the step. Gregor wants this fixed first. A `gc()` after
  each step would show whether the 18 GB is live or uncollected garbage.
- UMAP starts at 23.3 GB, peaks at 34.9 (+11.6 GB own). Optimisation 394.5 s
  of 439.6 s on 98.3M edges.
- DGE adds only 3.3 GB (21.9 -> 25.2), so the Wilcoxon ranking is not the
  peak; the retained kNN/sNN memory is.
- Load 1212 s: CSR -> CSC conversion 457 s (scatter 381 s over 8 phases,
  uneven at 25 to 80 s; compress + write 76 s), plus about 340 s unaccounted
  after "Loading observations data from h5ad into the DuckDB".
- HVG 184 s is all "Calculated gene statistics"; MT proportions in QC 86 s.
  Gregor suspects gene chunk decompression shared with the CSC scatter;
  unmeasured until decompression and statistics are timed apart.

## Docs out of date (remind Gregor, do not edit unasked)

README and `docs/methods.md`: Tahoe not described; methods says loaders run at
a default `csc_mem_gb = 8`, but `NULL` means a single phase and the 8 comes
from the run scripts; BPCells uint32 conversion, MT 15% and Scanpy in-memory
DGE need disclosing; Tahoe scores not described.
