# Seurat with the counts on disk as a BPCells matrix.
# Usage: Rscript seurat_bpcells.R <data_dir> <out_dir> <scratch_dir>

source("/bench/pipelines/common.R")
suppressPackageStartupMessages({
  library(Seurat)
  library(BPCells)
  library(harmony)
})

# Seurat >= 5.6.0 C++ kernels default to one thread
setThreads(threads, verbose = FALSE)

# each plate opened lazily from its h5ad and bound on the shared genes, then
# the pre-filter as in bixverse: genes in >= 5 cells first, then cells with
# >= 100 genes and >= 250 UMIs, written once as the BPCells store
step("load", {
  mats <- lapply(names(h5_paths), function(p) {
    m <- open_matrix_anndata_hdf5(h5_paths[[p]])
    colnames(m) <- paste0(p, "_", colnames(m))
    m
  })
  shared <- Reduce(intersect, lapply(mats, rownames))
  mat <- do.call(cbind, lapply(mats, function(m) m[shared, ]))
  meta <- rbindlist(lapply(names(h5_paths), function(p) {
    cols <- unique(c(truth_col, batch_col, dge_col))
    dt <- as.data.table(setNames(lapply(cols, function(cl) read_h5ad_col(h5_paths[[p]], "/obs", cl)), cols))
    dt[, cell_id := paste0(p, "_", h5ad_index(h5_paths[[p]], "/obs"))]
  }))
  gene_detected <- rowSums(binarize(mat, threshold = 0))
  mat <- mat[gene_detected >= min_cells, ]
  cell_detected <- colSums(binarize(mat, threshold = 0))
  keep <- cell_detected >= 100 & colSums(mat) >= 250
  # Tahoe stores integer counts as float32, which BPCells warns compresses
  # poorly; written as uint32 as that warning advises
  mat <- write_matrix_dir(convert_matrix_type(mat[, keep], "uint32_t"), file.path(scratch, "counts"))
  md <- data.frame(meta[keep], row.names = meta$cell_id[keep])
  obj <- CreateSeuratObject(counts = mat, meta.data = md)
})

step("qc", {
  obj[["percent.mt"]] <- PercentageFeatureSet(obj, features = intersect(mt_ids, rownames(obj)))
  obj <- subset(obj, subset = percent.mt <= mt_max & nCount_RNA >= 750 & nFeature_RNA >= 250)
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
  obj <- RunHarmony(obj, group.by.vars = batch_col, ncores = threads, verbose = FALSE)
})

step("knn_snn", {
  obj <- FindNeighbors(obj, reduction = "harmony", dims = 1:30, k.param = 15, verbose = FALSE)
})

step("umap", {
  obj <- RunUMAP(obj, reduction = "harmony", dims = 1:30, verbose = FALSE)
})

# BPCells' marker test wants gene-major storage, so the subset's data layer is
# transposed once, as its warning advises; the cost stays in this step
step("dge", {
  sub <- subset(obj, cells = colnames(obj)[obj[[dge_col, drop = TRUE]] %in% c(dge_case, dge_ctrl)])
  LayerData(sub, layer = "data") <- transpose_storage_order(
    LayerData(sub, layer = "data"),
    outdir = file.path(scratch, "dge_gene_major"),
    tmpdir = scratch
  )
  Idents(sub) <- dge_col
  markers <- as.data.table(FindMarkers(sub, ident.1 = dge_case, ident.2 = dge_ctrl, verbose = FALSE), keep.rownames = "gene")
})

labels <- data.table(
  cell_id = colnames(obj),
  truth = obj[[truth_col, drop = TRUE]],
  batch = obj[[batch_col, drop = TRUE]]
)
write_embs(list(harmony = Embeddings(obj, "harmony"), umap = Embeddings(obj, "umap")), labels)
fwrite(markers, file.path(out, "markers.csv"))

message(sprintf("cells after QC: %d, DGE genes: %d", ncol(obj), nrow(markers)))
print(sessionInfo())
