#!/usr/bin/env bash
# Usage: [DATA=dir] [WALL=18000] [R_IMAGE=scbench-r:local] tahoe/run.sh <tool>
#   tool: bixverse | seurat_bpcells | scanpy_dask | cytearc
# Every *.h5ad in DATA is one plate; each tool reads them all natively.
# Container capped at 48 GB RAM plus 8 GB swap, 8 cores. A run is killed once
# it has run for WALL seconds in total.
set -euo pipefail
tool="$1"
root="$(cd "$(dirname "$0")" && pwd)"
data="${DATA:-$HOME/Desktop/tahoe100m_h5ad}"
dataset="${DATASET:-tahoe}"
out="$root/results/$dataset/$tool${TAG:+_$TAG}"
rm -rf "$out"; mkdir -p "$out"

# Tahoe defaults: cell lines as the truth, Harmony on sublibraries, DGE of one
# drug against the vehicle; MT_MAX in percent, inclusive
TRUTH_COL="${TRUTH_COL:-cell_line}"; BATCH_COL="${BATCH_COL:-sublibrary}"
DGE_COL="${DGE_COL:-drug}"; DGE_CTRL="${DGE_CTRL:-DMSO_TF}"; DGE_CASE="${DGE_CASE:-Gemcitabine}"
MT_MAX="${MT_MAX:-15}"

case "$tool" in
  scanpy_dask) image=scbench-py; cmd=(python /bench/pipelines/scanpy_dask.py /data /out) ;;
  cytearc) image=scbench-cytearc; cmd=(python /bench/pipelines/cytearc_pipeline.py /data /out /scratch) ;;
  *) image="${R_IMAGE:-scbench-r:local}"; cmd=(Rscript "/bench/pipelines/$tool.R" /data /out /scratch) ;;
esac

docker volume rm -f scbench-scratch > /dev/null
docker volume create scbench-scratch > /dev/null
docker rm -f scbench-run > /dev/null 2>&1 || true

wall="${WALL:-18000}"
# poll rather than one long sleep, so killing the subshell leaves no timer behind
(
  start=$(date +%s)
  while sleep 10; do
    if [ $(( $(date +%s) - start )) -gt "$wall" ]; then
      touch "$out/TIMEOUT"
      docker kill scbench-run > /dev/null 2>&1
      break
    fi
  done
) &
watchdog=$!

status=0
docker run --rm --name scbench-run --cpus=8 --memory="${MEM:-48g}" --memory-swap="${MEMSWAP:-56g}" \
  -e OMP_NUM_THREADS=8 -e OPENBLAS_NUM_THREADS=8 -e RAYON_NUM_THREADS=8 \
  -e CHUNK="${CHUNK:-50000}" -e BIX_CSC_GB="${BIX_CSC_GB:-8}" -e GENE_COL="${GENE_COL:-}" \
  -e MT_MAX="$MT_MAX" -e TRUTH_COL="$TRUTH_COL" -e BATCH_COL="$BATCH_COL" -e DGE_COL="$DGE_COL" -e DGE_CTRL="$DGE_CTRL" -e DGE_CASE="$DGE_CASE" \
  -v "$data:/data:ro" \
  -v "$out:/out" \
  -v "$root/pipelines:/bench/pipelines:ro" \
  -v scbench-scratch:/scratch \
  "$image" /out "${cmd[@]}" || status=$?
kill "$watchdog" 2> /dev/null || true
# record what the tool left on disk (its store), then drop it
docker run --rm -v scbench-scratch:/s --entrypoint du "$image" -sk /s 2> /dev/null | cut -f1 > "$out/scratch_kb" || true
docker volume rm -f scbench-scratch > /dev/null
[ -f "$out/TIMEOUT" ] && echo "exit=124" >> "$out/log.txt"
exit "$status"
