# /// script
# requires-python = ">=3.12"
# dependencies = ["polars>=1.30"]
# ///
"""Per step wall time and peak memory. Usage: summarise.py <results/dataset>"""

import sys
from pathlib import Path

import polars as pl

GB = 1024**3
rows = []
for tool_dir in sorted(p for p in Path(sys.argv[1]).iterdir() if (p / "steps.csv").exists()):
    steps = pl.read_csv(tool_dir / "steps.csv")
    mem = pl.read_csv(tool_dir / "mem.csv")
    for s in steps.iter_rows(named=True):
        # widen by one sample either side so short steps still catch a reading
        win = mem.filter(pl.col("t").is_between(s["start"] - 1, s["end"] + 1))
        rows.append(
            {
                "tool": tool_dir.name,
                "step": s["step"],
                "wall_s": round(s["end"] - s["start"], 1),
                "peak_anon_gb": round(win["anon_bytes"].max() / GB, 2),
                "peak_swap_gb": round(win["swap_bytes"].max() / GB, 2),
            }
        )

df = pl.DataFrame(rows)
pl.Config.set_tbl_rows(100)
wide = df.pivot(on="tool", index="step", values=["wall_s", "peak_anon_gb"])
print(wide)
print(
    df.group_by("tool").agg(
        pl.col("wall_s").sum().alias("total_s"),
        pl.col("peak_anon_gb").max(),
        pl.col("peak_swap_gb").max(),
    )
)
