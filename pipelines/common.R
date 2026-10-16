# Shared by the R pipelines. Expects commandArgs: <data_dir> <out_dir> <scratch_dir>

suppressPackageStartupMessages(library(data.table))

args <- commandArgs(trailingOnly = TRUE)
data <- args[1]
out <- args[2]
scratch <- args[3]
threads <- 8L

steps_file <- file.path(out, "steps.csv")
cat("step,start,end\n", file = steps_file)

step <- function(name, expr) {
  start <- as.numeric(Sys.time())
  force(expr)
  end <- as.numeric(Sys.time())
  cat(sprintf("%s,%.3f,%.3f\n", name, start, end), file = steps_file, append = TRUE)
  message(sprintf(">>> %s: %.1f s <<<", name, end - start))
}

genes <- fread(file.path(data, "all_genes.csv"))
meta <- fread(file.path(data, "cell_metadata.csv"))
mt_ids <- genes[grepl("^MT-", gene_name), gene_id]

# simulated data: DGE on the true groups, plus the outputs score.py needs.
# Real data: DGE one-vs-rest over samples, a workload that is the same for
# every tool, unlike their clusters.
truth <- file.exists(file.path(data, "cells_truth.tsv.gz"))
dge_col <- if (truth) "Group" else "sample"

# embs: named list of cells x dims matrices with cell ids as rownames;
# markers: data.table(group, gene, score), score signed, higher = more up
write_truth_outputs <- function(hvg = NULL, embs = list(), markers = NULL) {
  if (!is.null(hvg)) fwrite(data.table(gene = hvg), file.path(out, "hvg.csv"))
  for (n in names(embs)) {
    fwrite(
      data.table(cell_id = rownames(embs[[n]]), embs[[n]]),
      file.path(out, sprintf("emb_%s.csv.gz", n))
    )
  }
  if (!is.null(markers)) fwrite(markers, file.path(out, "markers.csv"))
}
