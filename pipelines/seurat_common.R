# Downstream Seurat steps shared by the standard and BPCells pipelines.
# Expects `obj` (a Seurat object after the pre-filter) and common.R sourced.

# Seurat >= 5.6.0 C++ kernels default to one thread
setThreads(threads, verbose = FALSE)

step("qc", {
  obj[["percent.mt"]] <- PercentageFeatureSet(obj, features = intersect(mt_ids, rownames(obj)))
  obj <- subset(obj, subset = percent.mt < 5 & nCount_RNA >= 750 & nFeature_RNA >= 250)
})

step("normalise", {
  obj <- NormalizeData(obj, verbose = FALSE)
})

step("hvg", {
  obj <- FindVariableFeatures(obj, nfeatures = 2000, verbose = FALSE)
})

step("pca", {
  obj <- ScaleData(obj, verbose = FALSE)
  obj <- RunPCA(obj, npcs = 30, verbose = FALSE)
})

step("harmony", {
  obj <- RunHarmony(obj, group.by.vars = "sample", ncores = threads, verbose = FALSE)
})

step("knn_snn", {
  obj <- FindNeighbors(obj, reduction = "harmony", dims = 1:30, k.param = 15, verbose = FALSE)
})

step("cluster", {
  obj <- FindClusters(obj, resolution = 1, algorithm = 4, verbose = FALSE)
})

step("umap", {
  obj <- RunUMAP(obj, reduction = "harmony", dims = 1:30, verbose = FALSE)
})

step("dge", {
  Idents(obj) <- dge_col
  # On BPCells, FindAllMarkers skips presto and runs BPCells::marker_features
  # per group, which needs gene-major storage and otherwise transposes the whole
  # matrix on every call. Transpose the data layer once, as its warning advises;
  # the cost stays in this step.
  if (exists("on_bpcells")) {
    LayerData(obj, layer = "data") <- BPCells::transpose_storage_order(
      LayerData(obj, layer = "data"),
      outdir = file.path(scratch, "data_gene_major"),
      tmpdir = scratch
    )
  }
  markers <- as.data.table(FindAllMarkers(obj, verbose = FALSE))
})

# all score.py inputs before the tSNE steps, so a tSNE timeout only loses its rows
clusters <- data.table(cell_id = colnames(obj), cluster = obj$seurat_clusters)
fwrite(clusters, file.path(out, "clusters.csv"))
emb <- function(r) Embeddings(obj, reduction = r)
if (truth) {
  write_truth_outputs(
    hvg = VariableFeatures(obj),
    embs = list(pca = emb("pca"), harmony = emb("harmony"), umap = emb("umap")),
    markers = markers[, .(group = cluster, gene, score = sign(avg_log2FC) * -log10(pmax(p_val, 1e-300)))]
  )
}

step("tsne_default", {
  obj <- RunTSNE(obj, reduction = "harmony", dims = 1:30, num_threads = threads)
})
if (truth) write_truth_outputs(embs = list(tsne = emb("tsne")))

step("tsne_fft", {
  obj <- RunTSNE(
    obj,
    reduction = "harmony",
    dims = 1:30,
    tsne.method = "FIt-SNE",
    fast_tsne_path = "/opt/FIt-SNE/bin/fast_tsne",
    nthreads = threads,
    reduction.name = "tsne_fft",
    reduction.key = "tSNEfft_"
  )
})

message(sprintf("cells after QC: %d, clusters: %d", nrow(clusters), uniqueN(clusters$cluster)))
print(sessionInfo())
