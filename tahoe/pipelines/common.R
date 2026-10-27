# Shared by the R pipelines. Expects commandArgs: <data_dir> <out_dir> <scratch_dir>

suppressPackageStartupMessages(library(data.table))

args <- commandArgs(trailingOnly = TRUE)
data <- args[1]
out <- args[2]
scratch <- args[3]
threads <- 8L

truth_col <- Sys.getenv("TRUTH_COL")
batch_col <- Sys.getenv("BATCH_COL")
dge_col <- Sys.getenv("DGE_COL")
dge_ctrl <- Sys.getenv("DGE_CTRL")
dge_case <- Sys.getenv("DGE_CASE")

# one plate per file, named by the file name up to the first underscore
h5_paths <- sort(Sys.glob(file.path(data, "*.h5ad")))
names(h5_paths) <- sub("_.*", "", sub("\\.h5ad$", "", basename(h5_paths)))

steps_file <- file.path(out, "steps.csv")
cat("step,start,end\n", file = steps_file)

step <- function(name, expr) {
  start <- as.numeric(Sys.time())
  force(expr)
  end <- as.numeric(Sys.time())
  cat(sprintf("%s,%.3f,%.3f\n", name, start, end), file = steps_file, append = TRUE)
  message(sprintf(">>> %s: %.1f s <<<", name, end - start))
}

# an obs/var column of an h5ad, categorical (codes + categories) or plain
read_h5ad_col <- function(path, group, col) {
  node <- file.path(group, col)
  x <- if (rhdf5::h5readAttributes(path, node)[["encoding-type"]] == "categorical") {
    cats <- as.character(rhdf5::h5read(path, file.path(node, "categories")))
    cats[as.integer(rhdf5::h5read(path, file.path(node, "codes"))) + 1L]
  } else {
    as.vector(rhdf5::h5read(path, node))
  }
  rhdf5::h5closeAll()
  x
}

h5ad_index <- function(path, group) {
  read_h5ad_col(path, group, rhdf5::h5readAttributes(path, group)[["_index"]])
}

# gene symbols live in the var index unless GENE_COL names a var column
gene_col <- Sys.getenv("GENE_COL")
var_names <- if (nzchar(gene_col)) read_h5ad_col(h5_paths[1], "/var", gene_col) else h5ad_index(h5_paths[1], "/var")
mt_ids <- h5ad_index(h5_paths[1], "/var")[grepl("^MT-", var_names)]

# embs: named list of cells x dims matrices in the row order of labels;
# labels: data.table(cell_id, truth, batch). Written for a random 200k cells.
write_embs <- function(embs, labels) {
  set.seed(42L)
  idx <- sort(sample.int(nrow(labels), min(nrow(labels), 200000L)))
  fwrite(labels[idx], file.path(out, "score_cells.csv.gz"))
  for (n in names(embs)) {
    fwrite(as.data.table(embs[[n]][idx, , drop = FALSE]), file.path(out, sprintf("emb_%s.csv.gz", n)))
  }
}
