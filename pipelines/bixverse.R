# bixverse pipeline. Usage: Rscript bixverse.R <data_dir> <out_dir> <scratch_dir>

source("/bench/pipelines/common.R")
suppressPackageStartupMessages(library(bixverse))

# BIX_KNN sets the kNN for the sNN graph, BIX_TSNE_KNN the one tSNE builds
# internally (k = 3 x perplexity). nndescent uses extract_knn as in the big
# data vignette.
knn_method <- Sys.getenv("BIX_KNN", "kmknn")
tsne_knn_method <- Sys.getenv("BIX_TSNE_KNN", "kmknn")
knn_params <- list(knn_method = knn_method)
if (knn_method == "nndescent") knn_params$extract_knn <- TRUE

# load includes the pre-filter (genes in >= 5 cells, then cells with >= 100
# genes and >= 250 UMIs) and the log-normalisation, fused in one streaming pass
# cap on the CSR to CSC conversion buffers, as in the big data vignette
csc_mem_gb <- as.numeric(Sys.getenv("BIX_CSC_GB", "8"))

qc_param <- params_sc_min_quality(
  min_unique_genes = 100L,
  min_lib_size = 250L,
  min_cells = 5L,
  target_size = 1e4
)

step("load", {
  sce <- SingleCells(dir_data = scratch)
  sce <- if (Sys.getenv("INPUT", "mtx") == "h5ad") {
    load_h5ad(
      object = sce,
      h5_path = file.path(data, "DGE.h5ad"),
      sc_qc_param = qc_param,
      csc_mem_gb = csc_mem_gb
    )
  } else {
    load_mtx(
      object = sce,
      sc_mtx_io_param = params_sc_mtx_io(
        path_mtx = file.path(data, "DGE.mtx"),
        path_obs = file.path(data, "cell_metadata.csv"),
        path_var = file.path(data, "all_genes.csv"),
        cells_as_rows = TRUE,
        has_hdr = TRUE
      ),
      sc_qc_param = qc_param,
      csc_mem_gb = csc_mem_gb
    )
  }
})

# LOAD_ONLY=1: stop once the on-disk store is written, to measure its size
if (Sys.getenv("LOAD_ONLY") == "1") quit(save = "no")

step("qc", {
  var <- get_sc_var(object = sce)
  mt <- intersect(mt_ids, var$gene_id)
  # simulated data has no MT genes, and an empty gene set is an error
  if (length(mt) > 0) {
    sce <- gene_set_proportions_sc(object = sce, gene_set_list = list(MT = mt))
    qc_df <- sce[[c("cell_id", "lib_size", "nnz", "MT")]]
  } else {
    qc_df <- sce[[c("cell_id", "lib_size", "nnz")]][, MT := 0]
  }
  # MT comes back as a proportion or a percentage depending on version
  mt_cut <- if (max(qc_df$MT, na.rm = TRUE) <= 1) 0.05 else 5
  keep <- qc_df[MT < mt_cut & lib_size >= 750 & nnz >= 250, cell_id]
  sce <- set_cells_to_keep(sce, keep)
})

step("hvg", {
  sce <- find_hvg_sc(object = sce, hvg_no = 2000L)
})

step("pca", {
  sce <- calculate_pca_sc(object = sce, no_pcs = 30L)
})

step("harmony", {
  sce <- harmony_v2_sc(object = sce, batch_column = "sample")
})

step("knn_snn", {
  sce <- find_neighbours_sc(
    object = sce,
    embd_to_use = "harmony_v2",
    neighbours_params = params_sc_neighbours(knn = knn_params)
  )
})

step("cluster", {
  sce <- find_clusters_sc(object = sce, res = 1.0, name = "leiden")
})

# cluster_fast: k-means to 4 x sqrt(n) centroids, kNN graph (k = 15) over the
# centroids, Leiden at resolutions 1 and 2 on the same k-means, labels handed
# back to the cells
step("cluster_fast", {
  fc <- fast_cluster_sc(
    object = sce,
    embd_to_use = "harmony_v2",
    resolutions = c(1.0, 2.0),
    fc_params = params_sc_fast_cluster(
      n_centroids = as.integer(4 * sqrt(nrow(get_embedding(sce, "harmony_v2")))),
      algorithm = "leiden"
    ),
    .verbose = FALSE
  )
  fc_dt <- get_data(fc)
  setnames(fc_dt, c("res_1", "res_2"), c("leiden_fast", "leiden_fast_r2"))
  sce <- add_sc_new_obs(sce, fc_dt)
})

step("umap", {
  sce <- umap_sc(object = sce, embd_to_use = "harmony_v2")
})

# bixverse lowercases obs column names on load
step("dge", {
  markers <- find_all_markers_sc(sce, column_of_interest = tolower(dge_col), .verbose = FALSE)
})

# all score.py inputs before the tSNE steps, so a tSNE timeout only loses its rows
clusters <- sce[[c("cell_id", "leiden")]]
fwrite(clusters, file.path(out, "clusters.csv"))
fwrite(sce[[c("cell_id", "leiden_fast")]], file.path(out, "clusters_fast.csv"))
fwrite(sce[[c("cell_id", "leiden_fast_r2")]], file.path(out, "clusters_fast_r2.csv"))
if (truth) {
  write_truth_outputs(
    hvg = get_gene_names_from_idx(sce, get_hvg(sce), rust_based = TRUE),
    embs = list(
      pca = get_embedding(sce, "pca"),
      harmony = get_embedding(sce, "harmony_v2"),
      umap = get_embedding(sce, "umap")
    ),
    markers = markers[, .(group = grp, gene = gene_id, score = z_scores)]
  )
}

step("tsne_default", {
  sce <- tsne_sc(
    object = sce,
    embd_to_use = "harmony_v2",
    perplexity = 30,
    approx_type = "bh",
    knn_method = tsne_knn_method
  )
})
if (truth) write_truth_outputs(embs = list(tsne = get_embedding(sce, "tsne")))

step("tsne_fft", {
  sce <- tsne_sc(
    object = sce,
    embd_to_use = "harmony_v2",
    slot_name = "tsne_fft",
    perplexity = 30,
    approx_type = "fft_3k",
    knn_method = tsne_knn_method
  )
})

# tsne_quick: the quick-and-dirty Barnes-Hut of qdtsne (depth-capped tree,
# repulsion per leaf), at the scrapper row's settings: theta = 1, 500 iterations, 250
# early exaggeration at 12, max depth 7. Not a standard Barnes-Hut tSNE.
# tsne_sc does not take "bh_qd" yet, so call the manifoldsR function it wraps
step("tsne_quick", {
  harmony <- get_embedding(sce, "harmony_v2")
  tsne_quick <- manifoldsR::tsne(
    data = harmony,
    perplexity = 30,
    approx_type = "bh_qd",
    knn_method = tsne_knn_method,
    tsne_params = manifoldsR::params_tsne(n_epochs = 500L, theta = 1, max_depth = 7L),
    .verbose = FALSE
  )
  rownames(tsne_quick) <- rownames(harmony)
})
if (truth) write_truth_outputs(embs = list(tsne_quick = tsne_quick))

message(sprintf(
  "cells after QC: %d, clusters: %d, fast clusters: %d (res 1), %d (res 2)",
  nrow(clusters),
  uniqueN(clusters$leiden),
  uniqueN(sce[["leiden_fast"]]),
  uniqueN(sce[["leiden_fast_r2"]])
))
print(sessionInfo())
