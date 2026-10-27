"""CyteArc warm start: reopen the store the last cold run left in scratch.
Usage: cytearc_warm.py <data_dir> <out_dir> <scratch_dir>"""

import sys
import time
from pathlib import Path

import cytearc


def main():
    out, scratch = Path(sys.argv[2]), Path(sys.argv[3])
    cytearc.configure_output(level="WARNING", progress=False)
    # only the reopen: later steps would return the cold run's stored artifacts
    start = time.time()
    ds = cytearc.DataStore(str(scratch / "cytearc.zarr"))
    end = time.time()
    with open(out / "steps.csv", "w") as steps:
        steps.write(f"step,start,end\nload,{start},{end}\n")
    print(f"cells: {ds.cells.N}, genes: {ds.RNA.feats.N}")


if __name__ == "__main__":
    main()
