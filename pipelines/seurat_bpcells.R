# Seurat with the counts on disk as a BPCells matrix.
# Usage: Rscript seurat_bpcells.R <data_dir> <out_dir> <scratch_dir>

source("/bench/pipelines/common.R")
suppressPackageStartupMessages({
  library(Seurat)
  library(BPCells)
  library(harmony)
})

# pre-filter as in bixverse: genes in >= 5 cells first, then cells with
# >= 100 genes and >= 250 UMIs
step("load", {
  mat <- import_matrix_market(
    file.path(data, "DGE.mtx"),
    outdir = file.path(scratch, "raw"),
    row_names = meta$bc_wells,
    col_names = genes$gene_id,
    row_major = TRUE,
    tmpdir = scratch
  )
  mat <- t(mat)
  gene_detected <- rowSums(binarize(mat, threshold = 0))
  mat <- mat[gene_detected >= 5, ]
  cell_detected <- colSums(binarize(mat, threshold = 0))
  keep <- cell_detected >= 100 & colSums(mat) >= 250
  mat <- write_matrix_dir(mat[, keep], file.path(scratch, "counts"))
  md <- data.frame(meta[keep], row.names = meta$bc_wells[keep])
  obj <- CreateSeuratObject(counts = mat, meta.data = md)
})

# LOAD_ONLY=1: stop once the on-disk store is written, to measure its size
if (Sys.getenv("LOAD_ONLY") == "1") quit(save = "no")

on_bpcells <- TRUE
source("/bench/pipelines/seurat_common.R")
