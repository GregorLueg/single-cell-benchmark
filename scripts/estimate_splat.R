# Fit Splat parameters on a PBMC subsample, so the simulations have PBMC-like
# means, library sizes and dispersion.
# Usage: Rscript scripts/estimate_splat.R <parse_dir> <out_json> [n_cells]

suppressPackageStartupMessages({
  library(data.table)
  library(Matrix)
  library(splatter)
})

args <- commandArgs(trailingOnly = TRUE)
data <- args[1]
out <- args[2]
n_cells <- if (length(args) > 2) as.integer(args[3]) else 5000L

genes <- fread(file.path(data, "all_genes.csv"))
meta <- fread(file.path(data, "cell_metadata.csv"))

set.seed(42L)
pick <- sort(sample(nrow(meta), min(4L * n_cells, nrow(meta))))
# cells x genes, 1-based, two header lines
trip <- fread(file.path(data, "DGE.mtx"), skip = 2, col.names = c("i", "j", "x"))
trip <- trip[i %in% pick]
counts <- sparseMatrix(
  i = trip$j,
  j = match(trip$i, pick),
  x = trip$x,
  dims = c(nrow(genes), length(pick))
)
rm(trip)

# fit on cells that pass the benchmark QC, so simulated cells pass it too
mt <- grepl("^MT-", genes$gene_name)
lib <- colSums(counts)
keep <- colSums(counts > 0) >= 250 & lib >= 750 & colSums(counts[mt, ]) / lib < 0.05
counts <- counts[, which(keep)[seq_len(min(n_cells, sum(keep)))]]
counts <- counts[rowSums(counts > 0) >= 5, ]
message(sprintf("fitting on %d cells x %d genes", ncol(counts), nrow(counts)))

fit <- splatEstimate(as.matrix(counts))
writeLines(
  jsonlite::toJSON(getParams(fit, slotNames(fit)), auto_unbox = TRUE, digits = NA, pretty = TRUE),
  out
)
