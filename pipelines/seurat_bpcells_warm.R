# Seurat + BPCells warm start: reopen the filtered matrix the last cold run
# left in scratch. Usage: Rscript seurat_bpcells_warm.R <data_dir> <out_dir> <scratch_dir>

source("/bench/pipelines/common.R")
suppressPackageStartupMessages({
  library(Seurat)
  library(BPCells)
})

step("load", {
  mat <- open_matrix_dir(file.path(scratch, "counts"))
  md <- data.frame(
    meta[match(colnames(mat), meta$bc_wells)],
    row.names = colnames(mat)
  )
  obj <- CreateSeuratObject(counts = mat, meta.data = md)
})

message(sprintf("cells: %d, genes: %d", ncol(obj), nrow(obj)))
