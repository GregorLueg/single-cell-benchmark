# /// script
# requires-python = ">=3.12"
# dependencies = ["polars>=1.30"]
# ///
"""Markdown tables per dataset: wall time per step, failures marked at the step
where they happened. Usage: tables.py <results_dir> [dataset ...]"""

import re
import sys
from pathlib import Path

import polars as pl

GB = 1024**3
STEPS = ["load", "qc", "normalise", "hvg", "pca", "harmony", "knn_snn", "cluster",
         "umap", "tsne_default", "tsne_matched", "tsne_fft"]
TOOL_STEPS = {
    "bixverse": [s for s in STEPS if s not in ("normalise", "tsne_matched")],
    "scanpy": [s for s in STEPS if s != "tsne_matched"],
    "scrapper": [s for s in STEPS if s != "tsne_fft"],
    "seurat": [s for s in STEPS if s != "tsne_matched"],
}
# column -> result dir name, in display order
COLUMNS = {
    "bixverse mtx": ["bixverse_mtx_snn_nndescent", "bixverse_mtx", "bixverse"],
    "bixverse h5ad": ["bixverse_h5ad"],
    "bixverse GPU*": ["bixverse_gpu"],
    "Scanpy mtx": ["scanpy_mtx", "scanpy"],
    "Scanpy h5ad": ["scanpy_h5ad"],
    "scrapper": ["scrapper"],
    "Seurat std": ["seurat_standard"],
    "Seurat BPCells": ["seurat_bpcells"],
}


def family(name):
    return next(k for k in TOOL_STEPS if name.startswith(k))


def load_run(d):
    log = (d / "log.txt").read_text(errors="ignore")
    m = re.findall(r"^exit=(\d+)", log, re.M)
    status = int(m[-1]) if m else None
    mem = pl.read_csv(d / "mem.csv")
    steps = {}
    if (d / "steps.csv").stat().st_size > 20:
        for r in pl.read_csv(d / "steps.csv").iter_rows(named=True):
            steps[r["step"]] = r["end"] - r["start"]
    peak = mem["anon_bytes"].max() / GB
    swap = mem["swap_bytes"].max() / GB
    failed_at = None
    if status not in (0, None):
        order = TOOL_STEPS[family(d.name)]
        failed_at = next((s for s in order if s not in steps), order[-1])
        if (d / "TIMEOUT").exists():
            kind = "TIMEOUT"
        elif status == 137:
            kind = "OOM"
        else:
            kind = f"error {status}"
        failed_at = (failed_at, kind)
    elif status is None:
        failed_at = (next((s for s in TOOL_STEPS[family(d.name)] if s not in steps), "?"), "running")
    return steps, peak, swap, failed_at


def table(ds_dir):
    runs = {}
    for col, names in COLUMNS.items():
        d = next((ds_dir / n for n in names if (ds_dir / n / "mem.csv").exists()), None)
        if d:
            runs[col] = (d.name, *load_run(d))
    if not runs:
        return ""
    cols = list(runs)
    out = [f"### {ds_dir.name}", "", "| step | " + " | ".join(cols) + " |",
           "|---" * (len(cols) + 1) + "|"]
    for s in STEPS:
        cells = []
        for c in cols:
            name, steps, _, _, failed = runs[c]
            if s not in TOOL_STEPS[family(name)]:
                cells.append("n/a")
            elif s in steps:
                cells.append(f"{steps[s]:.1f}")
            elif failed and failed[0] == s:
                cells.append(f"**{failed[1]}**")
            else:
                cells.append("-")
        if any(x not in ("n/a", "-") for x in cells):
            out.append(f"| {s} | " + " | ".join(cells) + " |")
    out.append("| **total** | " + " | ".join(
        (f"**{sum(runs[c][1].values()):.0f}**" if not runs[c][4] else "failed") for c in cols) + " |")
    out.append("| **peak GB** | " + " | ".join(f"**{runs[c][2]:.1f}**" for c in cols) + " |")
    out.append("| peak swap GB | " + " | ".join(f"{runs[c][3]:.1f}" for c in cols) + " |")
    return "\n".join(out)


root = Path(sys.argv[1])
datasets = sys.argv[2:] or ["parse_100k", "parse_500k", "parse_full"]
print("\n\n".join(t for t in (table(root / d) for d in datasets if (root / d).exists()) if t))
