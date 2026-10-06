# One bixverse Harmony run on a fixed input, via the Rust entry points the
# harmony_sc / harmony_v2_sc / harmony_v2_gpu_sc wrappers call.
# Usage: Rscript run_bix.R <input.csv> <v1|v2|v2_b05|gpu|none> <out_prefix>
Sys.setenv(RAYON_NUM_THREADS = "8")
# same library as scripts/run_native.sh
.libPaths(c(Sys.getenv("BIX_RLIB", "rlib"), .libPaths()))
suppressPackageStartupMessages({
  library(data.table)
  library(bixverse)
})

args <- commandArgs(trailingOnly = TRUE)
impl <- args[2]
dt <- fread(args[1])
pca <- as.matrix(dt[, -(1:2)])
# as in the wrappers: 0-based integer codes, one vector per batch column
labels <- list(as.integer(factor(dt$batch)) - 1L)
k <- as.integer(min(round(nrow(pca) / 30), 100L))

if (impl == "none") quit(save = "no")
if (impl == "gpu") suppressPackageStartupMessages(library(bixverse.gpu))

params <- switch(impl,
  v1 = params_sc_harmony(k = k),
  v2 = params_sc_harmony_v2(k = k),
  v2_b05 = params_sc_harmony_v2(k = k, block_size = 0.05),
  gpu = params_sc_harmony_v2(k = k)
)
fn <- switch(impl, v1 = rs_harmony, v2 = rs_harmony_v2, v2_b05 = rs_harmony_v2, gpu = rs_harmony_v2_gpu)

t <- system.time(emb <- fn(pca = pca, harmony_params = params, batch_labels = labels, seed = 42L, verbose = 0L))[["elapsed"]]
fwrite(data.table(cell_id = dt$cell_id, emb), paste0(args[3], ".csv.gz"))
cat(sprintf("%.3f\n", t), file = paste0(args[3], ".time"))
