"""One harmonypy run on a fixed input. Usage: run_py.py <input.csv> <harmonypy|none> <out_prefix>"""

import sys
import time

import numpy as np
import pandas as pd

inp, impl, prefix = sys.argv[1:4]
df = pd.read_csv(inp)
pca = df.iloc[:, 2:].to_numpy(dtype=np.float64)
meta = df[["batch"]]
if impl == "none":
    sys.exit(0)

import harmonypy

t0 = time.perf_counter()
z = harmonypy.run_harmony(pca, meta, "batch", ncores=8, verbose=False).Z_corr
t = time.perf_counter() - t0
z = np.asarray(z if z.shape[0] == pca.shape[0] else z.T)
pd.DataFrame(z, index=df["cell_id"]).to_csv(f"{prefix}.csv.gz", index_label="cell_id")
open(f"{prefix}.time", "w").write(f"{t:.3f}\n")
