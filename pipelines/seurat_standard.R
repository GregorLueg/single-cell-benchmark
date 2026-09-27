# Seurat with an in-memory dgCMatrix, as in the standard tutorials.
# Usage: Rscript seurat_standard.R <data_dir> <out_dir> <scratch_dir>

source("/bench/pipelines/common.R")
suppressPackageStartupMessages({
  library(Seurat)
  library(harmony)
})

# pre-filter as in bixverse: genes in >= 5 cells first, then cells with
# >= 100 genes and >= 250 UMIs
step("load", {
  counts <- Matrix::readMM(file.path(data, "DGE.mtx"))
  counts <- as(Matrix::t(counts), "CsparseMatrix")
  dimnames(counts) <- list(genes$gene_id, meta$bc_wells)
  counts <- counts[Matrix::rowSums(counts > 0) >= 5, ]
  keep <- Matrix::colSums(counts > 0) >= 100 & Matrix::colSums(counts) >= 250
  counts <- counts[, keep]
  md <- data.frame(meta[keep], row.names = meta$bc_wells[keep])
  obj <- CreateSeuratObject(counts = counts, meta.data = md)
  rm(counts)
  invisible(gc())
})

source("/bench/pipelines/seurat_common.R")
