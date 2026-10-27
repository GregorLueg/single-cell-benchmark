# bixverse pipeline. Usage: Rscript bixverse.R <data_dir> <out_dir> <scratch_dir>

source("/bench/pipelines/common.R")
suppressPackageStartupMessages(library(bixverse))

# load includes the pre-filter (genes in >= 5 cells, then cells with >= 100
# genes and >= 250 UMIs) and the log-normalisation, fused in one streaming pass
# over all plates
qc_param <- params_sc_min_quality(
  min_unique_genes = 100L,
  min_lib_size = 250L,
  min_cells = 5L,
  target_size = 1e4
)

step("load", {
  prescan <- prescan_h5ad_files(h5_paths = h5_paths, gene_universe = "intersection")
  sce <- load_multi_h5ad(
    object = SingleCells(dir_data = scratch),
    prescan_result = prescan,
    sc_qc_param = qc_param,
    csc_mem_gb = as.numeric(Sys.getenv("BIX_CSC_GB", "8"))
  )
})

step("qc", {
  sce <- gene_set_proportions_sc(object = sce, gene_set_list = list(MT = mt_ids))
  qc_df <- sce[[c("cell_id", "lib_size", "nnz", "MT")]]
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

# bixverse lowercases obs column names on load
step("harmony", {
  sce <- harmony_v2_sc(object = sce, batch_column = tolower(batch_col))
})

step("knn_snn", {
  sce <- find_neighbours_sc(
    object = sce,
    embd_to_use = "harmony_v2",
    neighbours_params = params_sc_neighbours(knn = list(knn_method = "nndescent", extract_knn = TRUE))
  )
})

step("umap", {
  sce <- umap_sc(object = sce, embd_to_use = "harmony_v2")
})

step("dge", {
  obs <- sce[[c("cell_id", tolower(dge_col))]]
  grp <- obs[[2]]
  markers <- find_markers_sc(
    sce,
    cells_1 = obs$cell_id[grp == dge_case],
    cells_2 = obs$cell_id[grp == dge_ctrl],
    .verbose = FALSE
  )
})

harmony <- get_embedding(sce, "harmony_v2")
labels <- sce[[c("cell_id", tolower(truth_col), tolower(batch_col))]]
labels <- setnames(labels, c("cell_id", "truth", "batch"))[match(rownames(harmony), cell_id)]
write_embs(list(harmony = harmony, umap = get_embedding(sce, "umap")), labels)
fwrite(markers, file.path(out, "markers.csv"))

message(sprintf("cells after QC: %d, DGE genes: %d", nrow(harmony), nrow(markers)))
print(sessionInfo())
