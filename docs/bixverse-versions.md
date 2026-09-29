# bixverse across versions

The same workflow on three bixverse releases, everything else unchanged.
Seconds without tSNE / peak GB / clusters at resolution 1. The GPU peak is
native RSS. Older results live in `results/archive_bixverse_*`.

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

## Open items

- bixverse: the CSR to CSC transpose is still the largest part of a cold load.
- bixverse GPU: FFT tSNE on the device (manifolds-rs `fft_3k_gpu`) is not wired
  in yet.
- `scripts/to_h5ad.py` pins pandas < 3 because bixverse 0.5.3 could not read
  the gene count from `/var` without a plain dataset; recheck with 0.5.4.
- Warm start (reconnecting to converted data) for bixverse and Seurat +
  BPCells.
