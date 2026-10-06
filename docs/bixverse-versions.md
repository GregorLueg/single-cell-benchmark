# bixverse across versions

The same workflow on several bixverse releases, everything else unchanged.
Older results live in `results/archive_bixverse_*`.

## PBMC

Seconds without tSNE / peak GB / clusters at resolution 1. The GPU peak is
native RSS. The PBMC tables in [results](results.md#pbmc) are 0.5.5, within a
few seconds of 0.5.4.

| size | variant | 0.5.2 | 0.5.3 | 0.5.4 |
|---|---|---|---|---|
| 100k | mtx | 34 / 2.2 / 57 | 33 / 1.5 / 32 | 24 / 1.6 / 32 |
| 100k | h5ad | 29 / 2.1 / 54 | 27 / 1.5 / 32 | 21 / 1.6 / 32 |
| 100k | GPU | 23 / 4.3 / 40 | 27 / 4.1 / 32 | 13 / 4.3 / 33 |
| 500k | mtx | 190 / 8.4 / 517 | 187 / 6.4 / 44 | 149 / 6.3 / 43 |
| 500k | h5ad | 157 / 8.3 / 510 | 152 / 7.5 / 44 | 111 / 6.5 / 43 |
| 500k | GPU | - | 118 / 11.5 / 60 | 62 / 10.0 / 59 |
| full | mtx | 394 / 11.0 / 1,684 | 392 / 10.8 / 55 | 280 / 10.6 / 52 |
| full | h5ad | 342 / 17.5 / 1,682 | 327 / 17.2 / 53 | 233 / 9.0 / 53 |
| full | GPU | 218 / 18.2 / 2,804 | 249 / 16.8 / 92 | 124 / 16.1 / 91 |

- **0.5.3**: sNN pruning no longer fragments the graph (1,684 clusters down to
  55 on the full data); PCA 3x to 4x faster; GPU tSNE defaults reworked.
- **0.5.4**: streaming h5ad ingest and a memory-capped CSR to CSC conversion
  (`csc_mem_gb`). Full data load from h5ad 158 s to 71 s, peak 17.2 GB to 9.0
  GB; from mtx 232 s to 112 s. The GPU row also switched to GPU NNDescent for
  the kNN (9.0 s to 4.0 s at 500k).

## Simulation

Seconds without tSNE / Harmony seconds / peak GB / clusters (of them with 10
cells or fewer), for 12 true groups. "0.6.0 (first)" is the first local 0.6.0
build; "0.6.0" the current one, which the [results](results.md#simulation)
use. Both are local builds (TODO: replace with the r-universe release).

| size | variant | 0.5.7 | 0.6.0 (first) | 0.6.0 |
|---|---|---|---|---|
| 100k | mtx | 25 / 4.5 / 1.6 / 16 (3) | 22 / 0.9 / 1.5 / 13 (0) | 20 / 0.5 / 1.5 / 13 (0) |
| 100k | h5ad | 21 / 4.4 / 1.4 / 16 (3) | 18 / 0.8 / 1.5 / 13 (0) | 17 / 0.5 / 1.5 / 13 (0) |
| 100k | GPU | 13 / 1.3 / 3.0 / 42 (29) | 10 / 0.7 / 4.3 / 16 (3) | 11 / 0.6 / 4.1 / 16 (3) |
| 500k | mtx | 144 / 22.6 / 5.6 / 203 (190) | 113 / 3.3 / 6.8 / 19 (6) | 120 / 1.7 / 6.2 / 21 (8) |
| 500k | h5ad | 108 / 22.7 / 6.4 / 211 (198) | 93 / 3.5 / 5.7 / 16 (2) | 87 / 1.7 / 5.7 / 23 (10) |
| 500k | GPU | 53 / 4.8 / 11.4 / 489 (367) | 42 / 1.4 / 12.9 / 60 (28) | 44 / 1.3 / 13.0 / 71 (37) |
| 1M | mtx | 291 / 46.1 / 11.4 / 1,048 (1,035) | 242 / 8.0 / 10.9 / 41 (27) | 240 / 3.0 / 13.9 / 48 (35) |
| 1M | h5ad | 248 / 46.3 / 11.2 / 1,044 (1,032) | 207 / 6.4 / 14.4 / 46 (33) | 209 / 3.0 / 11.4 / 44 (29) |
| 1M | GPU | 108 / 9.1 / 18.3 / 1,506 (1,351) | 106 / 2.9 / 20.7 / 88 (52) | 108 / 2.1 / 17.8 / 90 (52) |

- **0.5.7**: `find_all_markers_sc` streams the gene-wise CSC view, one pass
  for all groups: 50.9 s to 0.7 s for 24 groups on 100k PBMC cells, with
  bit-identical statistics.
- **0.6.0 (first)**: the sNN re-attaches the islands pruning leaves. At 1M
  the clusters of 10 cells or fewer drop from 1,035 to 27 and the isolated
  pairs from 875 to none. Harmony v2 5x to 7x faster.
- **0.6.0**: Harmony again about 2x faster (8.0 s to 3.0 s at 1M), and the R
  wrapper takes the batch column with `[[1]]` instead of `unlist`, which built
  names for 0.12 s per million cells. The other steps move by load-time noise
  only.
- Peak memory at 1M swaps between runs inside the tSNE steps (11 to 14 GB);
  every step before tSNE stays under 9 GB.

## Open items

- bixverse: the CSR to CSC transpose is still the largest part of a cold load.
- bixverse: tight cliques of up to 10 cells (52 at 1M on the GPU) still come
  out as their own Leiden communities; a merge of small communities after
  clustering would remove them.
- bixverse: Harmony v2 needs about 1.1 GB more than harmonypy 2.1.0 at 1M. The
  candidates are a full n x k copy of R built and dropped on return
  (`r_to_mat`), `log_base` next to `base`, and double copies of the input and
  output around the FFI.
- bixverse: `additional_batch_columns` in the Harmony wrappers still go
  through `unlist`.
- bixverse: CellPhoneDB verbosity is not wired through, so the R package does
  not compile against bixverse-rs `23530c4` without the local patch
  ([methods](methods.md#versions)).
- `scripts/to_h5ad.py` pins pandas < 3 because bixverse 0.5.3 could not read
  the gene count from `/var` without a plain dataset; recheck with 0.6.0.
