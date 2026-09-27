# scrapper (libscran) pipeline on an in-memory dgCMatrix.
# Usage: Rscript scrapper.R <data_dir> <out_dir> <scratch_dir>

source("/bench/pipelines/common.R")
suppressPackageStartupMessages({
  library(scrapper)
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
  md <- data.frame(meta[keep])
  invisible(gc())
})

step("qc", {
  qc <- computeRnaQcMetrics(
    counts,
    subsets = list(mt = rownames(counts) %in% mt_ids),
    num.threads = threads
  )
  keep <- qc$subsets$mt < 0.05 & qc$sum >= 750 & qc$detected >= 250
  counts <- counts[, keep]
  md <- md[keep, ]
  sf <- qc$sum[keep]
})

step("normalise", {
  logn <- normalizeCounts(counts, centerSizeFactors(sf))
})

step("hvg", {
  var_stats <- modelGeneVariances(logn, num.threads = threads)
  hvgs <- chooseHighlyVariableGenes(var_stats$statistics$residuals, top = 2000)
})

step("pca", {
  pca <- runPca(logn[hvgs, ], number = 30, num.threads = threads)
})

step("harmony", {
  emb <- RunHarmony(
    t(pca$components),
    meta_data = md,
    vars_use = "sample",
    ncores = threads,
    verbose = FALSE
  )
})

step("knn_snn", {
  graph <- buildSnnGraph(t(emb), num.neighbors = 15, num.threads = threads)
})

step("cluster", {
  clusters <- clusterGraph(graph, method = "leiden", leiden.resolution = 1)
})

step("umap", {
  umap <- runUmap(t(emb), num.threads = threads)
})

# scrapper has no FFT tSNE, so only the default Barnes-Hut row
step("tsne_default", {
  tsne <- runTsne(t(emb), perplexity = 30, num.threads = threads)
})

res <- data.table(cell_id = md$bc_wells, cluster = clusters$membership)
fwrite(res, file.path(out, "clusters.csv"))
message(sprintf("cells after QC: %d, clusters: %d", nrow(res), uniqueN(res$cluster)))
print(sessionInfo())
