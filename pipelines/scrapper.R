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
  if (Sys.getenv("INPUT", "mtx") == "h5ad") {
    source("/bench/pipelines/h5ad_io.R")
    counts <- read_h5ad_counts(file.path(data, "DGE.h5ad"))
    meta <- meta[match(colnames(counts), bc_wells)]
  } else {
    counts <- Matrix::readMM(file.path(data, "DGE.mtx"))
    counts <- as(Matrix::t(counts), "CsparseMatrix")
    dimnames(counts) <- list(genes$gene_id, meta$bc_wells)
  }
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

# cluster_fast: k-means to 4 x sqrt(n) centroids, sNN graph (k = 15) over the
# centroids, Leiden at resolutions 1 and 2 on the same k-means, labels handed
# back to the cells.
# scrapper has no single call for this; composed from its primitives as in
# bluster's TwoStepParam
step("cluster_fast", {
  km <- clusterKmeans(t(emb), k = as.integer(4 * sqrt(nrow(emb))), num.threads = threads)
  centroid_graph <- buildSnnGraph(km$centers, num.neighbors = 15, num.threads = threads)
  clusters_fast <- lapply(c(1, 2), function(res) {
    clusterGraph(centroid_graph, method = "leiden", leiden.resolution = res)$membership[as.integer(km$clusters)]
  })
})

step("umap", {
  umap <- runUmap(t(emb), num.threads = threads)
})

step("dge", {
  markers <- scoreMarkers(logn, groups = md[[dge_col]], num.threads = threads)
})

# all score.py inputs before the tSNE steps, so a tSNE timeout only loses its rows
res <- data.table(cell_id = md$bc_wells, cluster = clusters$membership)
fwrite(res, file.path(out, "clusters.csv"))
fwrite(data.table(cell_id = md$bc_wells, cluster = clusters_fast[[1]]), file.path(out, "clusters_fast.csv"))
fwrite(data.table(cell_id = md$bc_wells, cluster = clusters_fast[[2]]), file.path(out, "clusters_fast_r2.csv"))
cells_named <- function(m) `rownames<-`(m, md$bc_wells)
if (truth) {
  write_truth_outputs(
    hvg = rownames(logn)[hvgs],
    embs = list(
      pca = cells_named(t(pca$components)),
      harmony = cells_named(emb),
      umap = cells_named(umap)
    ),
    markers = rbindlist(lapply(names(markers$auc), function(g) {
      data.table(group = g, gene = rownames(logn), score = markers$auc[[g]]$mean - 0.5)
    }))
  )
}

# tsne_quick: the quick-and-dirty Barnes-Hut of qdtsne (depth-capped tree,
# repulsion per leaf), at scrapper's defaults: theta = 1, 500 iterations, 250
# early exaggeration at 12, max depth 7. Not a standard Barnes-Hut tSNE.
step("tsne_quick", {
  tsne <- runTsne(t(emb), perplexity = 30, num.threads = threads)
})
if (truth) write_truth_outputs(embs = list(tsne_quick = cells_named(tsne)))

message(sprintf(
  "cells after QC: %d, clusters: %d, fast clusters: %d (res 1), %d (res 2)",
  nrow(res),
  uniqueN(res$cluster),
  uniqueN(clusters_fast[[1]]),
  uniqueN(clusters_fast[[2]])
))
print(sessionInfo())
