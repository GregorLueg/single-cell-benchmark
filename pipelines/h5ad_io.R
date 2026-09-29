# In-memory h5ad reader for the R pipelines (scrapper, Seurat standard).
# A cells x genes CSR /X is a genes x cells CSC, so it maps onto a dgCMatrix
# without a transpose.

read_h5ad_counts <- function(path) {
  x <- rhdf5::h5read(path, "/X", bit64conversion = "double")
  shape <- rhdf5::h5readAttributes(path, "/X")$shape
  obs_idx <- rhdf5::h5readAttributes(path, "/obs")[["_index"]]
  var_idx <- rhdf5::h5readAttributes(path, "/var")[["_index"]]
  counts <- new(
    "dgCMatrix",
    i = as.integer(x$indices),
    p = as.integer(x$indptr),
    x = as.double(x$data),
    Dim = as.integer(c(shape[2], shape[1])),
    Dimnames = list(
      as.character(rhdf5::h5read(path, file.path("/var", var_idx))),
      as.character(rhdf5::h5read(path, file.path("/obs", obs_idx)))
    )
  )
  rhdf5::h5closeAll()
  counts
}
