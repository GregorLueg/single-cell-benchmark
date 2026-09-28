# OSCA pipeline: SingleCellExperiment over an HDF5-backed DelayedArray, i.e.
# Bioconductor's out-of-core path (scuttle, scran, scater, BiocSingular,
# bluster). Reads the h5ad in place; nothing is realised in memory.
# Usage: Rscript osca.R <data_dir> <out_dir> <scratch_dir>

source("/bench/pipelines/common.R")
suppressPackageStartupMessages({
  library(SingleCellExperiment)
  library(HDF5Array)
  library(scuttle)
  library(scran)
  library(scater)
  library(BiocSingular)
  library(bluster)
  library(harmony)
})

bpparam <- BiocParallel::MulticoreParam(threads)
DelayedArray::setAutoBPPARAM(bpparam)

# pre-filter as in bixverse: genes in >= 5 cells first, then cells with
# >= 100 genes and >= 250 UMIs
step("load", {
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
  keep <- DelayedArray::colSums(counts > 0) >= 100 &
    DelayedArray::colSums(counts) >= 250
  counts <- counts[, keep]
  md <- meta[match(colnames(counts), bc_wells)]
  sce <- SingleCellExperiment(
    assays = list(counts = counts),
    colData = S4Vectors::DataFrame(md)
  )
})

step("qc", {
  qc <- perCellQCMetrics(
    sce,
    subsets = list(mt = rownames(sce) %in% mt_ids),
    BPPARAM = bpparam
  )
  sce <- sce[, qc$subsets_mt_percent < 5 & qc$sum >= 750 & qc$detected >= 250]
})

# OSCA defaults: centred library size factors, log2 with pseudo-count 1
step("normalise", {
  sce <- logNormCounts(sce, BPPARAM = bpparam)
})

step("hvg", {
  dec <- modelGeneVar(sce, BPPARAM = bpparam)
  hvgs <- getTopHVGs(dec, n = 2000)
})

# randomised SVD with deferred centring keeps the HDF5 matrix sparse; Billato
# et al. found it far faster than IRLBA on out-of-memory data
step("pca", {
  sce <- runPCA(
    sce,
    ncomponents = 30,
    subset_row = hvgs,
    BSPARAM = RandomParam(deferred = TRUE),
    BPPARAM = bpparam
  )
})

step("harmony", {
  reducedDim(sce, "harmony") <- RunHarmony(
    reducedDim(sce, "PCA"),
    meta_data = as.data.frame(colData(sce)),
    vars_use = "sample",
    ncores = threads,
    verbose = FALSE
  )
})

step("knn_snn", {
  graph <- makeSNNGraph(reducedDim(sce, "harmony"), k = 15, num.threads = threads)
})

step("cluster", {
  clusters <- igraph::cluster_leiden(
    graph,
    objective_function = "modularity",
    resolution = 1
  )$membership
})

step("umap", {
  sce <- runUMAP(sce, dimred = "harmony", n_threads = threads)
})

# scater's use_fitsne goes through snifter (Python via basilisk), so only the
# default Barnes-Hut row
step("tsne_default", {
  sce <- runTSNE(sce, dimred = "harmony", perplexity = 30, num_threads = threads)
})

res <- data.table(cell_id = colnames(sce), cluster = clusters)
fwrite(res, file.path(out, "clusters.csv"))
message(sprintf("cells after QC: %d, clusters: %d", nrow(res), uniqueN(res$cluster)))
print(sessionInfo())
