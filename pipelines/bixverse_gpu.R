# bixverse with bixverse.gpu (wgpu/Metal), run natively on macOS: Docker has
# no Metal access. Same steps and parameters as bixverse.R, GPU where it exists.
# Usage: Rscript bixverse_gpu.R <data_dir> <out_dir> <scratch_dir>

source(file.path(Sys.getenv("BENCH_DIR"), "pipelines", "common.R"))
suppressPackageStartupMessages({
  library(bixverse)
  library(bixverse.gpu)
})

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
  sce <- load_mtx(
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
})

step("qc", {
  var <- get_sc_var(object = sce)
  sce <- gene_set_proportions_sc(
    object = sce,
    gene_set_list = list(MT = var[grepl("^MT-", gene_name), gene_id])
  )
  qc_df <- sce[[c("cell_id", "lib_size", "nnz", "MT")]]
  mt_cut <- if (max(qc_df$MT, na.rm = TRUE) <= 1) 0.05 else 5
  keep <- qc_df[MT < mt_cut & lib_size >= 750 & nnz >= 250, cell_id]
  sce <- set_cells_to_keep(sce, keep)
})

step("hvg", {
  sce <- find_hvg_sc(object = sce, hvg_no = 2000L)
})

step("pca", {
  sce <- calculate_pca_gpu_sc(object = sce, no_pcs = 30L)
})

step("harmony", {
  sce <- harmony_v2_gpu_sc(object = sce, batch_column = "sample")
})

step("knn_snn", {
  # GPU NNDescent without CAGRA's beam search
  sce <- find_neighbours_gpu_sc(
    object = sce,
    embd_to_use = "harmony_gpu",
    knn_method = "nndescent",
    k = 15L,
    nn_params = params_nn_gpu(dist_metric = "euclidean", extract_knn = TRUE)
  )
})

step("cluster", {
  sce <- find_clusters_sc(object = sce, res = 1.0, name = "leiden")
})

step("umap", {
  sce <- umap_gpu_sc(object = sce, embd_to_use = "harmony_gpu")
})

step("tsne_default", {
  sce <- tsne_gpu_sc(
    object = sce,
    embd_to_use = "harmony_gpu",
    perplexity = 30,
    approx_type = "bh"
  )
})

step("tsne_fft", {
  sce <- tsne_gpu_sc(
    object = sce,
    embd_to_use = "harmony_gpu",
    slot_name = "tsne_fft",
    perplexity = 30,
    approx_type = "fft_3k_gpu"
  )
})

clusters <- sce[[c("cell_id", "leiden")]]
fwrite(clusters, file.path(out, "clusters.csv"))
message(sprintf("cells after QC: %d, clusters: %d", nrow(clusters), uniqueN(clusters$leiden)))
print(sessionInfo())
