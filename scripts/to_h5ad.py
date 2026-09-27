# /// script
# requires-python = ">=3.12"
# dependencies = ["anndata>=0.11", "scipy>=1.13", "pandas", "h5py"]
# ///
"""Convert a subsample dir (DGE.mtx, cells as rows) to DGE.h5ad with raw counts in X."""

import sys
from pathlib import Path

import anndata as ad
import numpy as np
import pandas as pd
import scipy.io

d = Path(sys.argv[1]).expanduser()
x = scipy.io.mmread(d / "DGE.mtx").tocsr().astype(np.float32)
obs = pd.read_csv(d / "cell_metadata.csv", index_col=0)
var = pd.read_csv(d / "all_genes.csv", index_col=0)
obs.index = obs.index.astype(str)
var.index = var.index.astype(str)
adata = ad.AnnData(X=x, obs=obs, var=var)
adata.write_h5ad(d / "DGE.h5ad")
print(adata)
