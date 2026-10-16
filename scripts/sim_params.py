"""splatter-sc params: the PBMC fit plus groups, DE and batches, with group
composition varying per batch.

Usage: sim_params.py <fit.json> <n_cells> <out_dir> > params.json
       splatter-sc params.json
"""

import json
import random
import sys

fit_path, n_cells, out_dir = sys.argv[1], int(sys.argv[2]), sys.argv[3]

N_BATCHES = 24
GROUP_PROB = [0.2, 0.15, 0.12, 0.1, 0.09, 0.08, 0.07, 0.06, 0.05, 0.04, 0.03, 0.04]
# the last group sits in 6 batches only (about 1% overall), the one before is
# missing from 8
RARE_IN = range(6)
ABSENT_IN = range(16, 24)

rng = random.Random(42)
batch_group_prob = []
for b in range(N_BATCHES):
    row = [p * rng.lognormvariate(0, 0.5) for p in GROUP_PROB]
    if b not in RARE_IN:
        row[-1] = 0.0
    if b in ABSENT_IN:
        row[-2] = 0.0
    batch_group_prob.append([round(p / sum(row), 6) for p in row])

params = json.load(open(fit_path))
for k in ["nCells", "nBatches", "nGroups", "path.from", "path.nSteps", "path.skew",
          "path.nonlinearProb", "path.sigmaFac"]:
    params.pop(k, None)
per = n_cells // N_BATCHES
params |= {
    "seed": 42,
    "method": "groups",
    "batchCells": [per + (b < n_cells % N_BATCHES) for b in range(N_BATCHES)],
    # tuned on 10k cells with Scanpy-style PCA: the fitted bcv.common (~0.36)
    # buries splatter's default DE (facLoc 0.1). With these, kNN group purity
    # is ~0.87 after Harmony, and batches visibly separate before it
    "batch.facLoc": 0.1,
    "batch.facScale": 0.5,
    "group.prob": GROUP_PROB,
    "de.prob": 0.03,
    "de.facLoc": 1.5,
    "batch.groupProb": batch_group_prob,
    "output": {"dir": out_dir, "layouts": ["parse", "h5ad"]},
}
json.dump(params, sys.stdout, indent=1)
