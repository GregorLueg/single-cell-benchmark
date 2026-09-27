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
  message(sprintf("%s: %.1f s", name, end - start))
}

genes <- fread(file.path(data, "all_genes.csv"))
meta <- fread(file.path(data, "cell_metadata.csv"))
mt_ids <- genes[grepl("^MT-", gene_name), gene_id]
