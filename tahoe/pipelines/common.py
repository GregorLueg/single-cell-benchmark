"""Shared by the Python pipelines. No side effects on import: CyteArc's spawn
workers re-import the pipeline script and everything it imports."""

import os
import time
from contextlib import contextmanager
from pathlib import Path

import numpy as np
import pandas as pd

MT_MAX = float(os.environ.get("MT_MAX", "15"))
TRUTH_COL = os.environ.get("TRUTH_COL", "")
BATCH_COL = os.environ.get("BATCH_COL", "")
DGE_COL = os.environ.get("DGE_COL", "")
DGE_CTRL = os.environ.get("DGE_CTRL", "")
DGE_CASE = os.environ.get("DGE_CASE", "")
GENE_COL = os.environ.get("GENE_COL", "")


def h5_paths(data: Path) -> dict[str, Path]:
    """One plate per file, named by the file name up to the first underscore."""
    return {p.stem.split("_")[0]: p for p in sorted(data.glob("*.h5ad"))}


def step_timer(out: Path):
    steps = open(out / "steps.csv", "w")
    steps.write("step,start,end\n")

    @contextmanager
    def step(name):
        start = time.time()
        yield
        steps.write(f"{name},{start},{time.time()}\n")
        steps.flush()
        print(f">>> {name}: {time.time() - start:.1f} s <<<", flush=True)

    return step


def write_embs(out: Path, embs: dict[str, np.ndarray], labels: pd.DataFrame):
    """embs in the row order of labels (cell_id, truth, batch); a random 200k cells."""
    rng = np.random.default_rng(42)
    idx = np.sort(rng.choice(len(labels), min(len(labels), 200_000), replace=False))
    labels.iloc[idx].to_csv(out / "score_cells.csv.gz", index=False)
    for name, emb in embs.items():
        pd.DataFrame(np.asarray(emb)[idx]).to_csv(out / f"emb_{name}.csv.gz", index=False)
