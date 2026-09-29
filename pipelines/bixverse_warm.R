# bixverse warm start: reconnect to the data the last cold run left in scratch.
# Usage: Rscript bixverse_warm.R <data_dir> <out_dir> <scratch_dir>

source("/bench/pipelines/common.R")
suppressPackageStartupMessages(library(bixverse))

step("load", {
  sce <- load_existing(SingleCells(dir_data = scratch), .verbose = FALSE)
})

message(sprintf("cells: %d, genes: %d", dim(sce)[1], dim(sce)[2]))
