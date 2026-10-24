# scrapper (libscran) pipeline on an in-memory dgCMatrix, or with INPUT=hdf5 on
# the h5ad read out of core as an HDF5-backed DelayedMatrix.
# Usage: Rscript scrapper.R <data_dir> <out_dir> <scratch_dir>

source("/bench/pipelines/common.R")
suppressPackageStartupMessages({
  library(scrapper)
  library(harmony)
})

# pre-filter as in bixverse: genes in >= 5 cells first, then cells with
# >= 100 genes and >= 250 UMIs
step("load", {
  if (Sys.getenv("INPUT", "mtx") == "hdf5") {
    # out of core: the h5ad stays on disk as an HDF5-backed DelayedMatrix;
    # beachmat.hdf5 hands scrapper a native tatami matrix, so the later steps
    # stream from the file without realising it
    suppressPackageStartupMessages({
      library(HDF5Array)
      library(beachmat.hdf5)
    })
    path <- file.path(data, "DGE.h5ad")
    counts <- H5ADMatrix(path)
    # H5ADMatrix finds no dimnames in our h5ad, whose indices are named
    var_idx <- rhdf5::h5readAttributes(path, "/var")[["_index"]]
    obs_idx <- rhdf5::h5readAttributes(path, "/obs")[["_index"]]
    dimnames(counts) <- list(
      as.character(rhdf5::h5read(path, file.path("/var", var_idx))),
      as.character(rhdf5::h5read(path, file.path("/obs", obs_idx)))
    )
    rhdf5::h5closeAll()
    counts <- counts[DelayedArray::rowSums(counts > 0) >= 5, ]
    keep <- DelayedArray::colSums(counts > 0) >= 100 & DelayedArray::colSums(counts) >= 250
    counts <- counts[, keep]
    md <- data.frame(meta[match(colnames(counts), bc_wells)])
  } else {
    if (Sys.getenv("INPUT", "mtx") == "h5ad") {
      source("/bench/pipelines/h5ad_io.R")
      counts <- read_h5ad_counts(file.path(data, "DGE.h5ad"))
      meta <- meta[match(colnames(counts), bc_wells)]
    } else {
      counts <- Matrix::readMM(file.path(data, "DGE.mtx"))
      counts <- as(Matrix::t(counts), "CsparseMatrix")
      dimnames(counts) <- list(genes$gene_id, meta$bc_wells)
    }
    # detection counts straight from the dgCMatrix slots: `counts > 0` would copy it
    counts <- counts[tabulate(counts@i + 1L, nrow(counts)) >= 5, ]
    keep <- diff(counts@p) >= 100 & Matrix::colSums(counts) >= 250
    counts <- counts[, keep]
    md <- data.frame(meta[keep])
  }
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
  pca <- runPca(logn, number = 30, subset = hvgs, num.threads = threads)
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

# neighbours as in runAllNeighborSteps from the scrapper vignette: one k = 15
# search shared by the sNN graph and UMAP. Called step by step to keep the
# per-step timings and threads. tSNE builds its own kNN, as in every framework.
step("knn_snn", {
  nn15 <- BiocNeighbors::findKNN(
    t(emb),
    k = 15,
    transposed = TRUE,
    BNPARAM = BiocNeighbors::AnnoyParam(),
    get.index = "transposed",
    get.distance = "transposed",
    num.threads = threads
  )
  graph <- buildSnnGraph(nn15, num.threads = threads)
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
  umap <- runUmap(nn15, num.threads = threads)
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

# tsne_quick: the quick-and-dirty Barnes-Hut of qdtsne (depth-capped tree), at
# scrapper's defaults: theta = 1, 500 iterations, 250 early exaggeration at 12,
# max depth 7, no leaf approximation. Not a standard Barnes-Hut tSNE.
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
