# /// script
# requires-python = ">=3.12"
# dependencies = ["polars>=1.30"]
# ///
"""Markdown tables from the benchmark results.

Usage: tables.py <results_dir> [dataset ...]          per-step tables
       tables.py --summary <results_dir> [splat]      one row per framework
       tables.py --long <results_dir>                 tidy CSV for plotting
       tables.py --warm <results_dir>                 cold vs warm load CSV
"""

import re
import sys
from pathlib import Path

import polars as pl

GB = 1024**3
STEPS = ["load", "qc", "normalise", "hvg", "pca", "harmony", "knn_snn", "cluster",
         "cluster_fast", "umap", "dge", "tsne_default", "tsne_fft", "tsne_quick"]
TOOL_STEPS = {
    "bixverse": [s for s in STEPS if s != "normalise"],
    "scanpy": [s for s in STEPS if s not in ("cluster_fast", "tsne_quick")],
    "scrapper": [s for s in STEPS if s not in ("tsne_default", "tsne_fft")],
    "seurat": [s for s in STEPS if s not in ("cluster_fast", "tsne_quick")],
    "cytearc": [s for s in STEPS if s != "cluster_fast" and not s.startswith("tsne")],
}
# alternative takes on a step: listed, but not in the totals
EXTRA = ("tsne", "cluster_fast")
LABELS = {"cluster_fast": "cluster_fast (qd)", "tsne_quick": "tsne_quick (qd)"}
# column -> result dir name, in display order
COLUMNS = {
    "bixverse mtx": ["bixverse_mtx_snn_nndescent", "bixverse_mtx", "bixverse"],
    "bixverse h5ad": ["bixverse_h5ad"],
    "bixverse GPU*": ["bixverse_gpu"],
    "bixverse MLX*": ["bixverse_mlx"],
    "Scanpy mtx": ["scanpy_mtx", "scanpy"],
    "Scanpy h5ad": ["scanpy_h5ad"],
    "Scanpy dask": ["scanpy_dask"],
    "scrapper mtx": ["scrapper"],
    "scrapper h5ad": ["scrapper_h5ad"],
    "scrapper HDF5": ["scrapper_hdf5"],
    "Seurat std mtx": ["seurat_standard"],
    "Seurat std h5ad": ["seurat_standard_h5ad"],
    "Seurat BPCells": ["seurat_bpcells"],
    "CyteArc mtx": ["cytearc"],
    "CyteArc h5ad": ["cytearc_h5ad"],
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
    # native runs: /usr/bin/time -l's peak footprint; their sampled RSS counts the mapped store
    fp = re.search(r"^\s*(\d+)\s+peak memory footprint", log, re.M)
    peak = (int(fp.group(1)) if fp else mem["anon_bytes"].max()) / GB
    swap = mem["swap_bytes"].max() / GB
    failed_at = None
    if status not in (0, None):
        # Scanpy on dask has no DGE step (Wilcoxon is unsupported there)
        order = [s for s in TOOL_STEPS[family(d.name)] if not (s == "dge" and d.name.endswith("dask"))]
        failed_at = next((s for s in order if s not in steps), order[-1])
        if (d / "TIMEOUT").exists():
            kind = "TIMEOUT"
        elif status == 137:
            kind = "OOM"
        elif "did not deliver a result" in log:
            # the kernel killed a forked BiocParallel worker, not the main process
            kind = "OOM (worker)"
        else:
            kind = f"error {status}"
        failed_at = (failed_at, kind)
    elif status is None:
        failed_at = (next((s for s in TOOL_STEPS[family(d.name)] if s not in steps), "?"), "running")
    return steps, peak, swap, failed_at


def collect(ds_dir):
    runs = {}
    for col, names in COLUMNS.items():
        d = next((ds_dir / n for n in names if (ds_dir / n / "mem.csv").exists()), None)
        if d:
            runs[col] = (d.name, *load_run(d))
    return runs


# framework -> (cold result dirs, warm result dir); the warm run is load only
WARM = {
    "bixverse": (["bixverse_mtx_snn_nndescent", "bixverse_mtx", "bixverse"], "bixverse_warm"),
    "Seurat BPCells": (["seurat_bpcells"], "seurat_bpcells_warm"),
}


def warm_table(ds_dir):
    rows = []
    for name, (cold, warm) in WARM.items():
        w = ds_dir / warm
        c = next((ds_dir / n for n in cold if (ds_dir / n / "mem.csv").exists()), None)
        if not (w / "mem.csv").exists() or c is None:
            continue
        cold_load = load_run(c)[0].get("load")
        warm_run = load_run(w)
        if warm_run[3] or "load" not in warm_run[0]:
            rows.append(f"| {name} | - | failed | - |")
        else:
            cold_s = f"{cold_load:.1f}" if cold_load is not None else "-"
            rows.append(f"| {name} | {cold_s} | {warm_run[0]['load']:.1f} | {warm_run[1]:.1f} |")
    if not rows:
        return ""
    return "\n".join([f"### {ds_dir.name}: warm start", "", "| framework | cold load s | warm load s | warm peak GB |",
                      "|---|---|---|---|", *rows])


def warm_long(root):
    rows = ["framework,size,start,seconds,peak_gb"]
    for ds in ["parse_100k", "parse_500k", "parse_full"]:
        for name, (cold, warm) in WARM.items():
            c = next((root / ds / n for n in cold if (root / ds / n / "mem.csv").exists()), None)
            w = root / ds / warm
            for start, d in (("cold", c), ("warm", w)):
                if d is None or not (d / "mem.csv").exists():
                    continue
                steps, peak, _, failed = load_run(d)
                if not failed and "load" in steps:
                    rows.append(f"{name},{ds},{start},{steps['load']:.2f},{peak:.2f}")
    return "\n".join(rows)


def table(ds_dir):
    runs = collect(ds_dir)
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
            out.append(f"| {LABELS.get(s, s)} | " + " | ".join(cells) + " |")
    out.append("| **total** | " + " | ".join(
        (f"**{sum(v for k, v in runs[c][1].items() if k != 'cluster_fast'):.0f}**" if not runs[c][4] else "failed")
        for c in cols) + " |")
    # a run that only failed in a tSNE step still has a total without tSNE
    out.append("| total without tSNE | " + " | ".join(
        (f"{sum(v for k, v in runs[c][1].items() if not k.startswith(EXTRA)):.0f}"
         if not runs[c][4] or runs[c][4][0].startswith("tsne") else "failed") for c in cols) + " |")
    out.append("| **peak GB** | " + " | ".join(f"**{runs[c][2]:.1f}**" for c in cols) + " |")
    out.append("| peak swap GB | " + " | ".join(f"{runs[c][3]:.1f}" for c in cols) + " |")
    scratch = {c: ds_dir / runs[c][0] / "scratch_kb" for c in cols}
    if any(p.exists() and p.read_text().strip() for p in scratch.values()):
        out.append("| on-disk store GB | " + " | ".join(
            f"{int(p.read_text()) / 1024**2:.1f}" if p.exists() and p.read_text().strip() else "-"
            for p in scratch.values()) + " |")
    if any("tsne_quick" in runs[c][1] or "cluster_fast" in runs[c][1] for c in cols):
        out += ["", "qd: quick and dirty. tsne_quick is the qdtsne Barnes-Hut (theta 1, 500 iterations, "
                "depth-capped tree), not a standard Barnes-Hut tSNE. cluster_fast is Leiden on k-means "
                "centroids, labels handed back to the cells. Neither counts towards the totals."]
    return "\n".join(out)


def summary(root, kind):
    sizes = ({"splat_100k": "100k", "splat_500k": "500k", "splat_1m": "1M"} if kind == "splat"
             else {"parse_100k": "100k", "parse_500k": "500k", "parse_full": "full"})
    per_size = {label: collect(root / ds) for ds, label in sizes.items()}
    cols = [c for c in COLUMNS if any(c in r for r in per_size.values())]
    out = ["| framework | " + " | ".join(sizes.values()) + " |", "|---" * (len(sizes) + 1) + "|"]
    for c in cols:
        cells = []
        for label in sizes.values():
            run = per_size[label].get(c)
            if run is None:
                cells.append("-")
                continue
            _, steps, peak, _, failed = run
            if failed and not failed[0].startswith("tsne"):
                cells.append(f"{failed[1]} at {failed[0]}")
            else:
                no_tsne = sum(v for k, v in steps.items() if not k.startswith(EXTRA))
                cells.append(f"{no_tsne:.0f} s, {peak:.1f} GB")
        out.append(f"| {c} | " + " | ".join(cells) + " |")
    return "\n".join(out)


def long(root):
    sizes = {"parse_100k": 69412, "parse_500k": 346259, "parse_full": 684932,
             "splat_100k": 96342, "splat_500k": 482409, "splat_1m": 964763}
    mem_rows = ["column,size,cells,step,seconds,peak_gb,status"]
    for ds, cells in sizes.items():
        for col, (name, steps, peak, _, failed) in collect(root / ds).items():
            order = TOOL_STEPS[family(name)]
            status = failed[1] if failed else "ok"
            for st in order:
                if st in steps:
                    mem_rows.append(f"{col},{ds},{cells},{st},{steps[st]:.2f},{peak:.2f},ok")
                elif failed and st == failed[0]:
                    mem_rows.append(f"{col},{ds},{cells},{st},,{peak:.2f},{status}")
    return "\n".join(mem_rows)


if sys.argv[1] == "--long":
    print(long(Path(sys.argv[2])))
elif sys.argv[1] == "--warm":
    print(warm_long(Path(sys.argv[2])))
elif sys.argv[1] == "--summary":
    print(summary(Path(sys.argv[2]), sys.argv[3] if len(sys.argv) > 3 else "parse"))
else:
    root = Path(sys.argv[1])
    datasets = sys.argv[2:] or ["parse_100k", "parse_500k", "parse_full"]
    print("\n\n".join(t for d in datasets if (root / d).exists() for t in (table(root / d), warm_table(root / d)) if t))
